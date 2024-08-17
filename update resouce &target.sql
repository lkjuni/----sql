--插入source和target列
ALTER TABLE road_shapefile ADD COLUMN source INTEGER;
ALTER TABLE road_shapefile ADD COLUMN target INTEGER;

-- 更新 source 列 （在节点表中找到 路段起点的 点的id
UPDATE road_shapefile SET source = n.id
FROM (
  SELECT r.gid AS road_id, n.id   --输出表格中有两个字段，分别是road、n.id ，其中AS road_id是给r.gid起了别名
  FROM road_shapefile r, nodes n  -- 这里的逗号 代表 笛卡尔积运算
  WHERE ST_DWithin(ST_StartPoint(r.geom), n.geom, 0.0001)
  ORDER BY  ST_Distance(ST_StartPoint(r.geom), n.geom)
) AS n
where road_shapefile."gid" = n.road_id

-- 更新 target 列
UPDATE road_shapefile SET target = n.id
FROM (
  SELECT r.gid AS road_id, n.id
  FROM road_shapefile r, nodes n
  WHERE ST_DWithin(ST_EndPoint(r.geom), n.geom, 0.0001)
  ORDER BY  r.gid,ST_Distance(ST_EndPoint(r.geom), n.geom)
) AS n
where road_shapefile."gid" = n.road_id