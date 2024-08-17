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
		geom GEOMETRY(POINT,3857) UNIQUE
	) ;
	
	-- 将道路几何分解为起点和终点并插入到 road_node 表中  *****错误** 同一个点 可能是 多个道路的端点，所以这样会引起同一个点重复插入，且id不同				
		-- 插入去重后的起始点
		INSERT INTO road_node (geom)
		SELECT DISTINCT ST_StartPoint(geom)
		FROM road_unsplited;

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
	
	
--STEP4：利用道路节点将现有道路进行进一步分割，将分割好的道路存入新的表格road_splited
	-- 创建 road_splited 表，存储分割后的道路
	CREATE TABLE road_splited (
		gid SERIAL PRIMARY KEY,
		geom GEOMETRY(LineString, 3857) -- 使用 EPSG:3857 坐标系
	);
	--将道路按节点进行分割，并插入到 road_splited 表中
	WITH nodes AS (
		SELECT ST_Collect(geom) AS geom
		FROM road_unsplited
	),
	buffered_nodes AS (
		SELECT ST_Collect(ST_Buffer(geom, 1)) AS geom -- ****调整 1 为合适的容差值（单位为坐标系的单位）
		FROM road_unsplited
	),
	split_roads AS (
		SELECT ST_Split(r.geom, n.geom) AS geom_collection
		FROM road_unsplited r, buffered_nodes n
	)

	-- 将分割后的道路插入到 road_splited 表中
	INSERT INTO road_splited (geom)
	SELECT (ST_Dump(geom_collection)).geom  
	FROM split_roads;						
	
--STEP5:补充target、source列为了对road_splited使用A*算法，所以road_splited需要补充 起点id和终点id	
	
	--插入source、target列
	ALTER TABLE road_splited ADD COLUMN source int;
	ALTER TABLE road_splited ADD COLUMN target int;

	--更新 source 列	 
	UPDATE road_splited SET source = n.id
	FROM
	(SELECT r.gid AS road_id, road_node.id   --定义输出的表格中有两个字段，分别是road、n.id ，其中AS road_id是给r.gid起了别名
	  FROM road_splited r, road_node   -- 这里的逗号 代表 笛卡尔积运算 
	  WHERE ST_DWithin(ST_StartPoint(r.geom), road_node.geom, 2)  --数据精度低，道路之间没有严丝合缝，所以该步骤的tolerance要高，否则找不到起点的id
	  --需要只保留最近的
	) AS n
	WHERE road_splited.gid = n.road_id AND (road_splited.source is NULL OR road_splited.source;
	
	
-- 更新 target 列
	UPDATE road_splited SET target = n.id
	FROM (
	  SELECT r.gid AS road_id, road_node.id
	  FROM road_splited r, road_node
	  WHERE ST_DWithin(ST_EndPoint(r.geom), road_node.geom, 2)
	) AS n
	where road_splited.gid = n.road_id
	--检查有无未匹配到起始点的道路
	--SELECT gid
	-- FROM road_splited
	-- WHERE (road_splited.source is NULL OR road_splited.target is NULL)


--STEP6:使用A*算法
	--创建表rout_node_list存储算法的结果
	CREATE TABLE rout_node_list (
		geom GEOMETRY(POINT,3857)
	    );

	--A*算法
WITH nodelist AS(
	SELECT  seq,
			node,
			(SELECT geom FROM road_node r WHERE r.id = node)  AS geom 
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
  seq,geom,
  CASE
    WHEN next_azimuth IS NULL THEN 'End of route'
    WHEN prev_azimuth IS NULL THEN 'Start route'
    WHEN abs(next_azimuth - prev_azimuth) < radians(15) THEN 'Continue straight'
    WHEN next_azimuth - prev_azimuth < 0 THEN 'Turn right'
    ELSE 'Turn left'
  END AS instruction
FROM
  angles;