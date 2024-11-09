DELIMITER $$

/*
   Author: Ardian Krasniqi - ardian.krasniqi@hotmail.com
   Date: 11/04/2020

   Stored Procedure: CodeGenerator_MySQL_DatabaseDocumentation_Generator
   Purpose:
       This procedure generates documentation for a specified table within the current database.
       It gathers details about the table's columns, including data types, nullability, 
       foreign key references, and comments. Additionally, it identifies dependencies on 
       other tables and stored procedures within the database. The output is formatted as an 
       HTML file containing the table's structure, column details, and dependency information.
       
   Parameters:
       @TableName (IN) - The name of the table to document (e.g., 'my_table').

   Output:
       An HTML file saved to the specified directory containing:
           1. Table structure and column definitions.
           2. Foreign key relationships with other tables.
           3. References from or dependencies on stored procedures within the database.
*/

CREATE PROCEDURE CodeGenerator_MySQL_DatabaseDocumentation_Generator(IN TableName VARCHAR(128))
BEGIN
    DECLARE TableDescription TEXT;

    -- Retrieve table description (using TABLE_COMMENT as MySQL's version of object description)
    SELECT TABLE_COMMENT INTO TableDescription
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = TableName;

    -- Create temporary table for column details
    CREATE TEMPORARY TABLE IF NOT EXISTS ColumnDetails (
        ColumnName VARCHAR(128),
        DataType VARCHAR(128),
        IsNullable VARCHAR(10),
        ForeignKeyReference VARCHAR(256),
        ForeignKeyColumnName VARCHAR(256),
        ForeignKeyName VARCHAR(128),
        IndexName VARCHAR(128),
        ObjectComment TEXT
    );

    -- Insert column details
    INSERT INTO ColumnDetails (ColumnName, DataType, IsNullable, ForeignKeyReference, ForeignKeyColumnName, ForeignKeyName, IndexName, ObjectComment)
    SELECT
        COLUMN_NAME,
        CONCAT(DATA_TYPE, IF(CHARACTER_MAXIMUM_LENGTH IS NOT NULL, CONCAT('(', CHARACTER_MAXIMUM_LENGTH, ')'), '')),
        IS_NULLABLE,
        IFNULL(REFERENCED_TABLE_NAME, '') AS ReferencedTable,
        IFNULL(REFERENCED_COLUMN_NAME, '') AS ReferencedColumn,
        CONSTRAINT_NAME AS ForeignKeyName,
        INDEX_NAME,
        COLUMN_COMMENT AS ObjectComment
    FROM INFORMATION_SCHEMA.COLUMNS c
    LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE fk ON fk.TABLE_SCHEMA = c.TABLE_SCHEMA
        AND fk.TABLE_NAME = c.TABLE_NAME
        AND fk.COLUMN_NAME = c.COLUMN_NAME
    LEFT JOIN INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc ON rc.CONSTRAINT_NAME = fk.CONSTRAINT_NAME
        AND rc.TABLE_SCHEMA = c.TABLE_SCHEMA
    LEFT JOIN INFORMATION_SCHEMA.STATISTICS idx ON idx.TABLE_SCHEMA = c.TABLE_SCHEMA
        AND idx.TABLE_NAME = c.TABLE_NAME
        AND idx.COLUMN_NAME = c.COLUMN_NAME
    WHERE c.TABLE_SCHEMA = DATABASE() AND c.TABLE_NAME = TableName;

    -- Initialize the HTML output
    SET @HtmlOutput = CONCAT(
        '<html><head><style>',
        'body {font-family: "Segoe UI";} ',
        'table {border-collapse: collapse; width: 100%; font-size: 10pt;} ',
        'th {background-color: darkgrey; color: white; font-weight: bold; border: 1px solid black; padding: 2px;} ',
        'td {border: 1px solid black; padding: 2px;} ',
        'tr:nth-child(even) {background-color: lightgrey;} ',
        'tr:nth-child(odd) {background-color: white;} ',
        '</style></head><body>',
        '<h1 style="font-size: 13pt; font-weight: bold; color:#091961;">', TableName, '</h1>',
        '<p style="font-size: 11pt;">', IFNULL(TableDescription, '-'), '</p>',
        '<h2 style="font-size: 12pt; font-weight: bold; color:#3399ff;">1. Column Definitions</h2>',
        '<table><tr><th>Column Name</th><th>Data Type</th><th>Is Nullable</th><th>Foreign Key Reference</th><th>Foreign Key Column</th><th>Foreign Key Name</th><th>Index Name</th><th>Object Comment</th></tr>'
    );

    -- Loop through ColumnDetails and add rows to the HTML
    DECLARE done INT DEFAULT FALSE;
    DECLARE ColumnName VARCHAR(128);
    DECLARE DataType VARCHAR(128);
    DECLARE IsNullable VARCHAR(10);
    DECLARE ForeignKeyReference VARCHAR(256);
    DECLARE ForeignKeyColumnName VARCHAR(256);
    DECLARE ForeignKeyName VARCHAR(128);
    DECLARE IndexName VARCHAR(128);
    DECLARE ObjectComment TEXT;

    DECLARE ColumnCursor CURSOR FOR
        SELECT ColumnName, DataType, IsNullable, ForeignKeyReference, ForeignKeyColumnName, ForeignKeyName, IndexName, ObjectComment
        FROM ColumnDetails;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN ColumnCursor;
    read_loop: LOOP
        FETCH ColumnCursor INTO ColumnName, DataType, IsNullable, ForeignKeyReference, ForeignKeyColumnName, ForeignKeyName, IndexName, ObjectComment;
        IF done THEN
            LEAVE read_loop;
        END IF;

        SET @HtmlOutput = CONCAT(@HtmlOutput, 
            '<tr><td>', ColumnName, '</td>',
            '<td>', DataType, '</td>',
            '<td>', IsNullable, '</td>',
            '<td>', ForeignKeyReference, '</td>',
            '<td>', ForeignKeyColumnName, '</td>',
            '<td>', ForeignKeyName, '</td>',
            '<td>', IndexName, '</td>',
            '<td>', IFNULL(ObjectComment, ''), '</td></tr>'
        );
    END LOOP;
    CLOSE ColumnCursor;

    SET @HtmlOutput = CONCAT(@HtmlOutput, '</table>');

    -- Temporary table for dependencies
    CREATE TEMPORARY TABLE IF NOT EXISTS Dependencies (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        TableName VARCHAR(128),
        TypeOfDependency VARCHAR(50),
        ObjectName VARCHAR(128),
        DependencyType VARCHAR(50),
        ObjectComment TEXT
    );

    -- Foreign key dependencies
    INSERT INTO Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, ObjectComment)
    SELECT DISTINCT TableName, 'Table', REFERENCED_TABLE_NAME, 'Parent', '-'
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = TableName AND REFERENCED_TABLE_NAME IS NOT NULL;

    INSERT INTO Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, ObjectComment)
    SELECT DISTINCT TableName, 'Table', TABLE_NAME, 'Child', '-'
    FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME = TableName;

    -- Stored procedure dependencies (searching for table name in procedure definitions)
    INSERT INTO Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, ObjectComment)
    SELECT DISTINCT TableName, 'Stored Procedure', ROUTINE_NAME, 'Dependent',
           IFNULL(ROUTINE_COMMENT, '-')
    FROM INFORMATION_SCHEMA.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
      AND ROUTINE_DEFINITION LIKE CONCAT('%', TableName, '%');

    -- Adding dependency table to HTML output
    SET @HtmlOutput = CONCAT(@HtmlOutput,
        '<h2 style="font-size: 12pt; font-weight: bold; color:#3399ff;">2. Dependencies</h2>',
        '<table><tr><th>ID</th><th>Table Name</th><th>Type Of Dependency</th><th>Object Name</th><th>Dependency Type</th><th>Object Comment</th></tr>'
    );

    -- Dependency rows
    DECLARE DependencyID INT;
    DECLARE TypeOfDependency VARCHAR(50);
    DECLARE ObjectName VARCHAR(128);
    DECLARE DependencyType VARCHAR(50);
    DECLARE DependencyComment TEXT;

    DECLARE DependencyCursor CURSOR FOR
        SELECT ID, TableName, TypeOfDependency, ObjectName, DependencyType, ObjectComment
        FROM Dependencies;

    SET done = FALSE;
    OPEN DependencyCursor;
    dep_loop: LOOP
        FETCH DependencyCursor INTO DependencyID, TableName, TypeOfDependency, ObjectName, DependencyType, DependencyComment;
        IF done THEN
            LEAVE dep_loop;
        END IF;

        SET @HtmlOutput = CONCAT(@HtmlOutput,
            '<tr><td>', DependencyID, '</td>',
            '<td>', TableName, '</td>',
            '<td>', TypeOfDependency, '</td>',
            '<td>', ObjectName, '</td>',
            '<td>', DependencyType, '</td>',
            '<td>', IFNULL(DependencyComment, '-'), '</td></tr>'
        );
    END LOOP;
    CLOSE DependencyCursor;

    SET @HtmlOutput = CONCAT(@HtmlOutput, '</table></body></html>');

    -- Export HTML to file
    SET @FilePath = CONCAT('/path/to/export/', TableName, '.html');  -- Change this path as needed
    SET @SqlExport = CONCAT("SELECT '", REPLACE(@HtmlOutput, "'", "''"), "' INTO OUTFILE '", @FilePath, "'");
    PREPARE stmt FROM @SqlExport;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

END$$

DELIMITER ;
