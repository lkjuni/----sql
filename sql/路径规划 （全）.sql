
-- 1. 创建 road_node 表，存储分解出的道路节点
CREATE TABLE road_node (
    id SERIAL PRIMARY KEY,
    geom GEOMETRY(Point, 3857) -- 使用 EPSG:3857 坐标系
);

-- 将道路几何分解为点并插入到 road_node 表中
INSERT INTO road_node (geom)
SELECT  (ST_DumpPoints(geom)).geom
FROM road_shapefile;

-- 2. 创建 road_splited 表，存储分割后的道路
CREATE TABLE road_splited (
    gid SERIAL PRIMARY KEY,
    geom GEOMETRY(LineString, 3857) -- 使用 EPSG:3857 坐标系
);

-- 3. 将道路按节点进行分割，并插入到 road_splited 表中
WITH nodes AS (
    SELECT ST_Collect(geom) AS geom
    FROM road_node
),
buffered_nodes AS (
    SELECT ST_Collect(ST_Buffer(geom, 1)) AS geom -- 调整 1 为合适的容差值（单位为坐标系的单位）
    FROM road_node
),
split_roads AS (
    SELECT ST_Split(r.geom, n.geom) AS geom_collection
    FROM road_shapefile r, buffered_nodes n
)
-- 将分割后的道路插入到 road_splited 表中
INSERT INTO road_splited (geom)
SELECT (ST_Dump(geom_collection)).geom
FROM split_roads;


	
--更新 resouce 列	
	UPDATE road_splited SET source = n.id
	FROM
	(SELECT r.gid AS road_id, road_node.id   --定义输出的表格中有两个字段，分别是road、n.id ，其中AS road_id是给r.gid起了别名
	  FROM road_splited r, road_node   -- 这里的逗号 代表 笛卡尔积运算
	  WHERE ST_DWithin(ST_StartPoint(r.geom), road_node.geom, 2)  --数据精度低，道路之间没有严丝合缝，所以该步骤的tolerance要高，否则找不到起点的id
	) AS n
	where road_splited.gid = n.road_id
	
	
-- 更新 target 列
	UPDATE road_splited SET target = n.id
	FROM (
	  SELECT r.gid AS road_id, road_node.id
	  FROM road_splited r, road_node
	  WHERE ST_DWithin(ST_EndPoint(r.geom), road_node.geom, 2)
	) AS n
	where road_splited.gid = n.road_id
	
--A*算法
CREATE TABLE rout_node_list (
	geom GEOMETRY
);


WITH nodelist AS(
SELECT node
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
		1,  -- 起点节点 ID
		114,  -- 终点节点 ID
		 directed:=false
		)
)


INSERT INTO rout_node_list
	SELECT geom 
	FROM road_node
	WHERE road_node.id in (SELECT * FROM nodelist)
	
	
