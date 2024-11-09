/*
   Author: Ardian Krasniqi - ardian.krasniqi@hotmail.com
   Date: 07/02/2020

   Stored Procedure: CodeGenerator_MSSQL_DatabaseDocumentation_Generator
   Purpose:
       This procedure generates documentation for a specified table within the current database.
       It gathers details about the table's columns, including data types, nullability, 
       foreign key references, and comments (MS_Description). Additionally, it identifies dependencies on 
       other tables and stored procedures within the database. The output is formatted as an 
       HTML file containing the table's structure, column details, and dependency information.
       
   Parameters:
       @TableName (IN) - The name of the table to document (e.g., 'my_table').

   Output:
       An HTML file saved to the specified directory containing:
           1. Table structure and column definitions.
           2. Foreign key relationships with other tables.
           3. References from or dependencies on stored procedures within the database.

    Requirements:
        MSSQL 2019+ with Machine Learning Services and Python Scripting Installed
*/


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[CodeGenerator_MSSQL_DatabaseDocumentation_Generator]
    @TableName NVARCHAR(128)
AS
BEGIN

-- Declare the variable to hold the table description STEP 2
DECLARE @TableDescription NVARCHAR(4000);

-- Retrieve the MS_Description for the table
SELECT @TableDescription = CONVERT(NVARCHAR(4000), prop.value)
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT JOIN sys.extended_properties prop ON
    prop.major_id = t.object_id AND
    prop.minor_id = 0 AND
    prop.name = 'MS_Description'
WHERE
    s.name + '.' + t.name = @TableName;

SELECT @TableDescription AS TableDescription

IF OBJECT_ID('tempdb..#ColumnDetails') IS NOT NULL DROP TABLE #ColumnDetails;

CREATE TABLE #ColumnDetails (
    ColumnName NVARCHAR(128),
    DataType NVARCHAR(128),
	IsNullable NVARCHAR(10),
    ForeignKeyReference NVARCHAR(256),
	ForeignKeyColumnName NVARCHAR(256),
    ForeignKeyName NVARCHAR(128),
    IndexName NVARCHAR(128),
    MS_Description NVARCHAR(4000),
    SQ_Description NVARCHAR(4000),
    SR_Description NVARCHAR(4000)
);

INSERT INTO #ColumnDetails (ColumnName, DataType, IsNullable, ForeignKeyReference, ForeignKeyColumnName, ForeignKeyName, IndexName, MS_Description, SQ_Description, SR_Description)
SELECT
    c.COLUMN_NAME,
    c.DATA_TYPE + COALESCE('(' + CAST(c.CHARACTER_MAXIMUM_LENGTH AS NVARCHAR) + ')', ''),
	c.IS_NULLABLE,
    OBJECT_SCHEMA_NAME(fkTable.referenced_object_id) + '.' + OBJECT_NAME(fkTable.referenced_object_id) AS ReferencedTable,
    COL_NAME(fkTable.referenced_object_id, fkTable.referenced_column_id) AS ReferencedColumn,
    fk.CONSTRAINT_NAME,
    idx.Name,
    CONVERT(NVARCHAR(4000), propMS.value),
    CONVERT(NVARCHAR(4000), propSQ.value),
    CONVERT(NVARCHAR(4000), propSR.value)
FROM 
    INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE fk ON
    fk.TABLE_SCHEMA = c.TABLE_SCHEMA AND
    fk.TABLE_NAME = c.TABLE_NAME AND
    fk.COLUMN_NAME = c.COLUMN_NAME
LEFT JOIN sys.foreign_key_columns fkTable ON
    fkTable.parent_object_id = OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME) AND
    fkTable.parent_column_id = COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'ColumnId')
LEFT JOIN sys.index_columns idxCol ON
    idxCol.object_id = OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME) AND
    idxCol.column_id = COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'ColumnId')
LEFT JOIN sys.indexes idx ON
    idx.object_id = idxCol.object_id AND
    idx.index_id = idxCol.index_id
LEFT JOIN sys.extended_properties propMS ON
    propMS.major_id = OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME) AND
    propMS.minor_id = COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'ColumnId') AND
    propMS.name = 'MS_Description'
LEFT JOIN sys.extended_properties propSQ ON
    propSQ.major_id = OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME) AND
    propSQ.minor_id = COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'ColumnId') AND
    propSQ.name = 'SQ_Description'
LEFT JOIN sys.extended_properties propSR ON
    propSR.major_id = OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME) AND
    propSR.minor_id = COLUMNPROPERTY(OBJECT_ID(c.TABLE_SCHEMA + '.' + c.TABLE_NAME), c.COLUMN_NAME, 'ColumnId') AND
    propSR.name = 'SR_Description'
WHERE
    c.TABLE_SCHEMA + '.' + c.TABLE_NAME = @TableName;

-- Declare the variable to hold the HTML output
DECLARE @HtmlOutput NVARCHAR(MAX) = '';

-- Initialize the HTML output with the basic HTML structure and styles
SET @HtmlOutput += 
    '<html><head>' +
    '<style>' +
    'body {font-family: ''Segoe UI'';}' +
    'table {border-collapse: collapse; width: 100%;font-size: 10pt; width:100%;}' +
    'th {background-color: darkgrey; color: white; font-weight: bold; border: 1px solid black; padding: 2px;}' +
    'td {border: 1px solid black; padding: 2px;}' +
    'tr:nth-child(even) {background-color: lightgrey;}' +
    'tr:nth-child(odd) {background-color: white;}' +
    '</style></head><body>';

-- Add the table name (Title), table description, and section title for column definitions
SET @HtmlOutput = @HtmlOutput + 
    '<h1 style="font-size: 13pt; font-weight: bold; color:#091961;">' + @TableName + '</h1>' +
    '<p style="font-size: 11pt;">' + (SELECT ISNULL(@TableDescription, '-')) + '</p>' +
    '<h2 style="font-size: 12pt; font-weight: bold; color:#3399ff;">1. Column Definitions</h2>';

-- Start the HTML table for column details with the new IsNullable column
SET @HtmlOutput = @HtmlOutput + 
    '<table><tr><th>Column Name</th><th>Data Type</th><th>Is Nullable</th><th>Foreign Key Reference</th><th>Foreign Key Column</th><th>Foreign Key Name</th><th>Index Name</th><th>MS_Description</th></tr>';

-- Declare the variable to hold the row data and add rows to the HTML table for each column detail
DECLARE @RowData NVARCHAR(MAX);
-- Update the variable to hold the row data and add rows to the HTML table for each column detail
SELECT @RowData = COALESCE(@RowData + '', '') + 
    '<tr>' +
    '<td>' + ColumnName + '</td>' +
    '<td>' + DataType + '</td>' +
    '<td>' + IsNullable + '</td>' +
	'<td>' + ISNULL(ForeignKeyReference, '') + '</td>' +
	'<td>' + ISNULL(ForeignKeyColumnName, '') + '</td>' +
	'<td>' + ISNULL(ForeignKeyName, '') + '</td>' +
	'<td>' + ISNULL(IndexName, '') + '</td>' +
	'<td>' + ISNULL(MS_Description, '') + '</td>' +
	'</tr>'
FROM #ColumnDetails;

-- Append the row data to the HTML output and close the HTML table
SET @HtmlOutput = @HtmlOutput + @RowData + '</table>';

-- Close the HTML table
SET @HtmlOutput = @HtmlOutput + '</table>';

IF OBJECT_ID('tempdb..#Dependencies') IS NOT NULL DROP TABLE #Dependencies;

CREATE TABLE #Dependencies (
    ID INT IDENTITY(1,1),
    TableName NVARCHAR(128),
    TypeOfDependency NVARCHAR(50), -- 'Table' or 'Stored Procedure'
    ObjectName NVARCHAR(128),
    DependencyType NVARCHAR(50), -- 'Depends On' or 'Is Dependent'
    MS_Description NVARCHAR(4000) -- Added column for MS_Description
);

-- Example: Insert parent and child dependencies for the specified table
-- Adjust the query according to your database schema and requirements

-- Insert parent dependencies
INSERT INTO #Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, MS_Description)
SELECT DISTINCT
    @TableName,
    'Table',
    OBJECT_NAME(referenced_object_id),
    'Parent',
	'-'
FROM sys.foreign_key_columns
WHERE parent_object_id = OBJECT_ID(@TableName);

-- Insert child dependencies
INSERT INTO #Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, MS_Description)
SELECT DISTINCT
    @TableName,
    'Table',
    OBJECT_NAME(parent_object_id),
    'Child',
	'-'
FROM sys.foreign_key_columns
WHERE referenced_object_id = OBJECT_ID(@TableName);

-- Insert stored procedure dependencies with MS_Description
INSERT INTO #Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, MS_Description)
SELECT DISTINCT
    @TableName,
    'Stored Procedure',
    OBJECT_NAME(referencing_id),
    'Child',
    ISNULL(CONVERT(NVARCHAR(4000), prop.value), '-')
FROM sys.sql_expression_dependencies dep
LEFT JOIN sys.procedures [proc] ON [proc].object_id = dep.referencing_id
LEFT JOIN sys.extended_properties prop ON prop.major_id = [proc].object_id
    AND prop.minor_id = 0
    AND prop.name = 'MS_Description'
WHERE dep.referenced_id = OBJECT_ID(@TableName);

-- Optionally, add dependencies where the table depends on stored procedures with MS_Description
INSERT INTO #Dependencies (TableName, TypeOfDependency, ObjectName, DependencyType, MS_Description)
SELECT DISTINCT
    @TableName,
    'Stored Procedure',
    OBJECT_NAME(referenced_id),
    'Parent',
    ISNULL(CONVERT(NVARCHAR(4000), prop.value), '-')
FROM sys.sql_expression_dependencies dep
LEFT JOIN sys.procedures [proc] ON [proc].object_id = dep.referenced_id
LEFT JOIN sys.extended_properties prop ON prop.major_id = [proc].object_id
    AND prop.minor_id = 0
    AND prop.name = 'MS_Description'
WHERE dep.referencing_id = OBJECT_ID(@TableName);

-- Add the section title for dependencies
SET @HtmlOutput = @HtmlOutput + '<h2 style="font-size: 12pt; font-weight: bold; color:#3399ff;">2. Dependencies</h2>';

-- Start the HTML table for dependencies
SET @HtmlOutput = @HtmlOutput + '<table><tr><th>ID</th><th>Table Name</th><th>Type Of Dependency</th><th>Object Name</th><th>Dependency Type</th><th>Description</th></tr>';

-- Declare a variable for dependency row data and add rows
DECLARE @DependencyRowData NVARCHAR(MAX) = '';

IF (SELECT COUNT(*) FROM #Dependencies) > 0
BEGIN
SELECT @DependencyRowData = COALESCE(@DependencyRowData + '', '') +
    '<tr>' +
    '<td>' + CAST(ID AS NVARCHAR(10)) + '</td>' +
    '<td>' + TableName + '</td>' +
    '<td>' + TypeOfDependency + '</td>' +
    '<td>' + ObjectName + '</td>' +
    '<td>' + DependencyType + '</td>' +
	'<td>' + MS_Description + '</td>' +
    '</tr>'
FROM #Dependencies;
END
-- Append the dependency row data to the HTML output and close the HTML table
SET @HtmlOutput = @HtmlOutput + @DependencyRowData + '</table>';

-- Close the HTML tags
SET @HtmlOutput = @HtmlOutput + '</body></html>';

DECLARE @Directory NVARCHAR(500) = (SELECT REPLACE([Value], '\' , '\\') FROM Administration.SystemConfig WHERE [Key] = 'PathToDocumentationExport')

-- Prepare the Python script
DECLARE @PythonScript NVARCHAR(MAX) = N'
import os
dir_path = "'+@Directory+'"
file_path = dir_path + "' + @TableName + '.html"
os.makedirs(dir_path, exist_ok=True)  # Create the directory if it does not exist

if Result is not None:  # Check if Result is not None before writing
    with open(file_path, "w") as file:
        file.write(Result)
        Result = Result.replace(''\r\n'', ''\n'')  # Replace Windows-style line endings
        with open(file_path, "w", newline=''\n'') as file:  # Ensure Unix-style line endings
            file.write(Result)';


-- Execute the Python script
EXEC sp_execute_external_script
    @language = N'Python',
    @script = @PythonScript,
    @params = N'@Result NVARCHAR(MAX)',
    @Result = @HtmlOutput;

END
GO
