	--插入建筑物节点在道路上的投影点
		CREATE TABLE building_projected (
			id int,
			geom GEOMETRY(POINT,3857),
			class int,
			name varchar

		);
																		
		INSERT INTO building_projected(name,class,geom)				
		SELECT DISTINCT ON (b.name)
				--b.gid AS building_id,
				b.name AS building_name,
                2,
				--ST_AsText(b.geom) AS building_location,
				--r.gid AS road_id,
				ST_ClosestPoint(r.geom, b.geom) AS projected_location
		FROM
				building_node b,
				sidewalk r
		WHERE
				ST_DWithin(r.geom, b.geom, 50)
        ORDER BY b.name,ST_Distance(r.geom, b.geom)



--STEP4：利用道路节点将现有道路进行进一步分割，将分割好的道路存入新的表格road_splited
	-- 创建 road_splited 表，存储分割后的道路
	CREATE TABLE road_splited (
		road_name varchar,
		gid SERIAL PRIMARY KEY,
		geom GEOMETRY(LineString, 3857) -- 使用 EPSG:3857 坐标系
	);  
	--将道路按节点进行分割，并插入到 road_splited 表中
	WITH buffered_nodes AS (
		SELECT ST_Collect(ST_Buffer(geom, 1)) AS geom -- ****调整 1 为合适的容差值（单位为坐标系的单位）
		FROM road_node
	),
	split_roads AS (
		SELECT r.name as road_name,ST_Split(r.geom, n.geom) AS geom_collection
		FROM road_unsplited r, buffered_nodes n
	)
	-- 将分割后的道路插入到 road_splited 表中
	INSERT INTO road_splited (road_name,geom)
	SELECT s.road_name ,(ST_Dump(geom_collection)).geom  AS geom
	FROM split_roads s;						
--STEP5:补充target、source列为了对road_splited使用A*算法，所以road_splited需要补充 起点id和终点id	

	--插入source、target列
	ALTER TABLE road_splited ADD COLUMN source int;
	ALTER TABLE road_splited ADD COLUMN target int;

	--更新 source 列	 
	UPDATE aaa SET source = n.id
	FROM
	(SELECT r.id AS road_id, all_nodes.id   --定义输出的表格中有两个字段，分别是road、n.id ，其中AS road_id是给r.gid起了别名
	  FROM aaa r, all_nodes   -- 这里的逗号 代表 笛卡尔积运算 
	  WHERE ST_DWithin(ST_StartPoint(r.geom), all_nodes.geom, 2)  --数据精度低，道路之间没有严丝合缝，所以该步骤的tolerance要高，否则找不到起点的id
	  --需要只保留最近的（未实现）
	) AS n
	WHERE aaa.id = n.road_id ;
	
	
-- 更新 target 列
	UPDATE aaa SET target = n.id
	FROM ( 
	  SELECT r.id AS road_id, all_nodes.id as id
	  FROM aaa r, all_nodes
	  WHERE ST_DWithin(ST_EndPoint(r.geom), all_nodes.geom, 2)
	) AS n
	where aaa.id = n.road_id;


	--检查有无未匹配到起始点的道路
delete 
	 FROM aaa
	WHERE (aaa.source is NULL OR aaa.target is NULL)



--STEP6:使用A*算法
	--创建表rout_node_list存储算法的结果
	CREATE TABLE rout_node_list (
		geom GEOMETRY(POINT,3857)
	    );

--A*算法
WITH nodelist AS(
    SELECT  seq,
            node,
            (SELECT ST_Transform(geom, 4326) FROM all_nodes r WHERE r.id = node) AS geom,
            (SELECT ST_X(ST_Transform(geom, 4326)) FROM all_nodes r WHERE r.id = node)  AS lon,
            (SELECT ST_Y(ST_Transform(geom, 4326)) FROM all_nodes r WHERE r.id = node)  AS lat      
    FROM pgr_astar(
            'SELECT id AS id,
                source, target, 
                ST_Length(geom) AS cost,
                ST_X(ST_StartPoint(geom)) AS x1, 
                ST_Y(ST_StartPoint(geom)) AS y1, 
                ST_X(ST_EndPoint(geom)) AS x2, 
                ST_Y(ST_EndPoint(geom)) AS y2     
             FROM aaa
            ',
            63,  -- 起点节点 ID
            102,  -- 终点节点 ID
            directed:=false
            )

    )
/* 	INSERT INTO rout_node_list
	SELECT geom 
	FROM all_nodes
	WHERE all_nodes.id in (SELECT node FROM nodelist) */


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
  FROM nodelist
  WHERE 
  )


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