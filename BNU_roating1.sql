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
		geom GEOMETRY(POINT,3857)
	) ;
	
	-- 将道路几何分解为起点和终点并插入到 road_node 表中
	INSERT INTO road_node (geom)
	SELECT ST_StartPoint(geom)
	FROM unsplited_road;
	
	INSERT INTO road_node (geom)
	SELECT ST_EndPoint(geom)
	FROM unsplited_road;
	--******还需要用qgis人工补充一些 两条道路的交叉点（相交，但是交点不是任意一条道路的端点）

--STEP4：利用道路节点将现有道路进行进一步分割，将分割好的道路存入新的表格road_splited
	-- 创建 road_splited 表，存储分割后的道路
	CREATE TABLE road_splited (
		gid SERIAL PRIMARY KEY,
		geom GEOMETRY(LineString, 3857) -- 使用 EPSG:3857 坐标系
	);
	--将道路按节点进行分割，并插入到 road_splited 表中
	WITH nodes AS (
		SELECT ST_Collect(geom) AS geom
		FROM unsplited_road
	),
	buffered_nodes AS (
		SELECT ST_Collect(ST_Buffer(geom, 1)) AS geom -- ****调整 1 为合适的容差值（单位为坐标系的单位）
		FROM unsplited_road
	),
	split_roads AS (
		SELECT ST_Split(r.geom, n.geom) AS geom_collection
		FROM unsplited_road r, buffered_nodes n
	)

	-- 将分割后的道路插入到 road_splited 表中
	INSERT INTO road_splited (geom)
	SELECT (ST_Dump(geom_collection)).geom   --******st_dump分割会生成很多在road_node中没有出现的端点，所以我们要抛弃之前的road_node,根据road_splited再新建一个节点表。
	FROM split_roads;						 --错误错误，如果 像上面那么做，每一条道路的确都能找到段点，但是很多道路之间就无法通过相同的端点进行连接了
	
	CREATE TABLE road_node02 (
		id SERIAL PRIMARY KEY,
		geom GEOMETRY(POINT,3857)
	) ;
	
	-- 将道路几何分解为起点和终点并插入到 road_node 表中   错误错误** 同一个点 可能是 多个道路的端点，所以这样会引起同一个点重复插入，且id不同
	INSERT INTO road_node02 (geom)						
	SELECT ST_StartPoint(geom)
	FROM road_splited;
	
	INSERT INTO road_node02 (geom)
	SELECT ST_EndPoint(geom)
	FROM road_splited;


--STEP5:补充target、source列为了对road_splited使用A*算法，所以road_splited需要补充 起点id和终点id
	
	ALTER TABLE road_splited ADD COLUMN target int;
	ALTER TABLE road_splited ADD COLUMN source int;

	--更新 souce 列	
	UPDATE road_splited SET source = n.id
	FROM
	(SELECT r.gid AS road_id, road_node02.id   --定义输出的表格中有两个字段，分别是road、n.id ，其中AS road_id是给r.gid起了别名
	  FROM road_splited r, road_node02   -- 这里的逗号 代表 笛卡尔积运算
	  WHERE ST_DWithin(ST_StartPoint(r.geom), road_node02.geom, 3)  --数据精度低，道路之间没有严丝合缝，所以该步骤的tolerance要高，否则找不到起点的id
	) AS n
	where road_splited.gid = n.road_id ;
	
	
	-- 更新 target 列
		UPDATE road_splited SET target = n.id
		FROM (
		  SELECT r.gid AS road_id, road_node02.id
		  FROM road_splited r, road_node02
		  WHERE ST_DWithin(ST_EndPoint(r.geom), road_node02.geom, 3)
		) AS n
		where road_splited.gid = n.road_id;
		--******若有些边找不到起点和终点，还需要用qgis人工补充一些节点
	
--STEP6:使用A*算法
	--创建表rout_node_list存储算法的结果
	CREATE TABLE rout_node_list (
		geom GEOMETRY(POINT,3857)
	    );

	--A*算法
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
			154,  -- 起点节点 ID
			114,  -- 终点节点 ID
			 directed:=false
			)
		
	)
	INSERT INTO rout_node_list
		SELECT geom 
		FROM road_node
		WHERE road_node.id in (SELECT * FROM nodelist)