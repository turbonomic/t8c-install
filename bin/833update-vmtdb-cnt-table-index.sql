-- Adding indexes on container stats tables to speed up queries for
-- container-related statistics and prevent query timeouts at
-- customers with large container estates.

DELIMITER $$

DROP PROCEDURE IF EXISTS `CreateIndex` $$
CREATE PROCEDURE Createindex
(
    given_table    VARCHAR(64) CHARACTER SET utf8mb4,
    given_index    VARCHAR(64) CHARACTER SET utf8mb4,
    given_columns  VARCHAR(64) CHARACTER SET utf8mb4
)
BEGIN

    DECLARE IndexIsThere INTEGER;

    SELECT COUNT(1) INTO IndexIsThere
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE table_name   = given_table
    AND   index_name   = given_index;

    IF IndexIsThere = 0 THEN
        SET @sqlstmt = CONCAT('CREATE INDEX',given_index,' ON',given_table,'(',given_columns,')');
        PREPARE st FROM @sqlstmt;
        EXECUTE st;
DEALLOCATE PREPARE st;
ELSE
SELECT CONCAT('Index ',given_index,' already exists on Table ',given_table) CreateindexErrorMessage;
END IF;

END $$

DELIMITER ;

call createindex('cnt_stats_by_hour','snapshot_time_idx','snapshot_time');
call createindex('cnt_stats_by_hour','property_type_idx','property_type');
call createindex('cnt_stats_by_hour','uuid_idx','uuid');

call createindex('cnt_stats_by_day','snapshot_time_idx','snapshot_time');
call createindex('cnt_stats_by_day','property_type_idx','property_type');
call createindex('cnt_stats_by_day','uuid_idx','uuid');

call createindex('cnt_stats_by_month','snapshot_time_idx','snapshot_time');
call createindex('cnt_stats_by_month','property_type_idx','property_type');
call createindex('cnt_stats_by_month','uuid_idx','uuid');

-- Cleanup by dropping the stored procedure at the end of the migration
DROP PROCEDURE IF EXISTS `CreateIndex`;