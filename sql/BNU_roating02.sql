--STEP1:在数据库中 加入postgis拓展
	CREATE EXTENSION postgis;
	SELECT postgis_full_version(); --查看postgis的版本
	CREATE EXTENSION pgrouting;

--STEP2:利用postgis bundle import软件 导入学校道路的shapefile文件
	--注意 **填写SRID  **打开option勾选 生成single geometry	
	--利用qgis人工修改一下road_splited,删除那些用不到的边，比如三环路，北邮……


--STEP3:创建道路节点表
	CREATE TABLE road_node (
		id SERIAL PRIMARY KEY,
		geom GEOMETRY(POINT,3857) UNIQUE,
		name varchar
	) ;

	-- 将道路几何分解为起点和终点并插入到 road_node 表中  *****错误** 同一个点 可能是 多个道路的端点，所以这样会引起同一个点重复插入，且id不同				
		-- 插入去重后的起始点
		INSERT INTO road_node (geom)
		SELECT DISTINCT ST_StartPoint(geom)
		FROM road_unsplited
		ON CONFLICT (geom) DO NOTHING; -- 如果存在重复点，则忽略插入操作
		-- 插入去重后的终点
		INSERT INTO road_node (geom)
		SELECT DISTINCT ST_EndPoint(geom)
		FROM road_unsplited
		ON CONFLICT (geom) DO NOTHING; -- 如果存在重复点，则忽略插入操作

	
	--******还需要用qgis人工补充一些 两条道路的交叉点（相交，但是交点不是任意一条道路的端点）
	CREATE TABLE supplement_node_ (   --存储该地图需要补的点,在qgis中插入点
		geom GEOMETRY(POINT,3857)
	) ;

	INSERT INTO road_node (geom)
	SELECT * FROM supplement_node_ 
	ON CONFLICT (geom) DO NOTHING;




--STEP6:使用A*算法
	--创建表rout_node_list存储算法的结果
	CREATE TABLE rout_node_list (
		geom GEOMETRY(POINT,3857)
	    );


--A*算法
WITH nodelist AS(
    SELECT  seq,
            node,
            (SELECT ST_Transform(geom, 4326) FROM road_node r WHERE r.id = node) AS geom,
            (SELECT ST_X(ST_Transform(geom, 4326)) FROM road_node r WHERE r.id = node)  AS lon,
            (SELECT ST_Y(ST_Transform(geom, 4326)) FROM road_node r WHERE r.id = node)  AS lat
           
    FROM pgr_astar(
            'SELECT gid AS id,
                source, target, 
                ST_Length(geom) AS cost,
                ST_X(ST_StartPoint(geom)) AS x1, 
                ST_Y(ST_StartPoint(geom)) AS y1, 
                ST_X(ST_EndPoint(geom)) AS x2, 
                ST_Y(ST_EndPoint(geom)) AS y2     
             FROM road_splited
            ',
            3,  -- 起点节点 ID
            109,  -- 终点节点 ID
             directed:=false
            )

    )

--  	INSERT INTO rout_node_list
--  		SELECT geom 
-- 		FROM road_node
-- 		WHERE road_node.id in (SELECT node FROM nodelist)


, angles AS(  
    SELECT
    seq,
    node,
    geom,
    lat,
    lon,
    LEAD(geom) OVER (ORDER BY seq) AS next_geom,
    LAG(geom) OVER (ORDER BY seq)  AS prev_geom,
    CASE
      WHEN LAG(geom) OVER (ORDER BY seq) IS NULL THEN NULL
      ELSE ST_Azimuth(LAG(geom) OVER (ORDER BY seq), geom)
    END AS prev_azimuth,
    CASE
      WHEN LEAD(geom) OVER (ORDER BY seq)  IS NULL THEN NULL
      ELSE ST_Azimuth(geom, LEAD(geom) OVER (ORDER BY seq))
    END AS next_azimuth
  FROM nodelist)


SELECT
  seq,lat,lon,next_azimuth, 
  CASE
    WHEN next_azimuth IS NULL THEN '到达终点'
    WHEN prev_azimuth IS NULL THEN '出发'
    WHEN abs(next_azimuth - prev_azimuth) < radians(15) THEN '继续直行'||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
    WHEN next_azimuth - prev_azimuth < 0 THEN '该路口右转，然后直行'||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
    ELSE '该路口左转，然后直行' ||ROUND(ST_Distance( ST_Transform(geom, 32633), ST_Transform(next_geom, 32633)))||'米'
  END AS instruction
FROM
  angles;