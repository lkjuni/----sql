
CREATE TABLE building_projected (
	building_name varchar ,
	geom GEOMETRY(POINT,3857)

);
											
											
INSERT INTO building_projected(building_name,geom)				
SELECT DISTINCT ON (b.gid)
		--b.gid AS building_id,
		b.buildingna AS building_name,
		--ST_AsText(b.geom) AS building_location,
		--r.gid AS road_id,
		ST_ClosestPoint(r.geom, b.geom) AS projected_location--,
		--ST_Distance(r.geom, b.geom) AS distance_to_road
FROM
		building_node b,
		road_unsplited r
WHERE
		ST_DWithin(r.geom, b.geom, 100)
ORDER BY
		b.gid, ST_Distance(r.geom, b.geom);
									

