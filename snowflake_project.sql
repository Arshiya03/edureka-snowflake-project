-- Step 1: Create SALES_DATA Table
CREATE OR REPLACE TABLE SALES_DATA (
    ORDER_ID STRING,
    REGION STRING,
    COUNTRY STRING,
    ITEM_TYPE STRING,
    SALES_CHANNEL STRING,
    ORDER_PRIORITY STRING,
    ORDER_DATE DATE,
    SHIP_DATE DATE,
    UNITS_SOLD INT,
    UNIT_PRICE FLOAT,
    UNIT_COST FLOAT,
    TOTAL_REVENUE FLOAT,
    TOTAL_COST FLOAT,
    TOTAL_PROFIT FLOAT
);

-- Step 2: Use the URL to Download the File and Upload to Snowflake Stage
-- Replace <storage_integration> with your Snowflake storage integration for external file access.
CREATE OR REPLACE STAGE SALES_STAGE
URL='https://raw.githubusercontent.com/Arshiya03/edureka-snowflake-project/main/Sales_Data.csv'
STORAGE_INTEGRATION = <storage_integration>
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- Step 3: Load CSV Data into SALES_DATA Table
COPY INTO SALES_DATA
FROM @SALES_STAGE
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- Step 4: Verify Total Record Count
SELECT COUNT(*) AS TOTAL_RECORDS FROM SALES_DATA;

-- Step 5: Unload SALES_DATA Table into Seven CSV Files Partitioned by REGION
COPY INTO @SALES_STAGE/partitioned_sales/
FROM SALES_DATA
PARTITION BY REGION
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- Step 6: Truncate SALES_DATA Table
TRUNCATE TABLE SALES_DATA;

-- Step 7: Create AGG_SALES_BY_COUNTRY Table
CREATE OR REPLACE TABLE AGG_SALES_BY_COUNTRY (
    REGION STRING,
    COUNTRY STRING,
    TOTAL_PROFIT FLOAT
);

-- Step 8: Load Partitioned Files into AGG_SALES_BY_COUNTRY
COPY INTO AGG_SALES_BY_COUNTRY
FROM @SALES_STAGE/partitioned_sales/
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- Aggregate Data for AGG_SALES_BY_COUNTRY
INSERT INTO AGG_SALES_BY_COUNTRY (REGION, COUNTRY, TOTAL_PROFIT)
SELECT REGION, COUNTRY, SUM(TOTAL_PROFIT)
FROM AGG_SALES_BY_COUNTRY
GROUP BY REGION, COUNTRY;

-- Step 9: Reload CSV Files into SALES_DATA with Transformation
COPY INTO SALES_DATA
FROM @SALES_STAGE/partitioned_sales/
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"')
ON_ERROR = 'CONTINUE';

-- Transform ORDER_PRIORITY Column
UPDATE SALES_DATA
SET ORDER_PRIORITY = CASE 
    WHEN ORDER_PRIORITY = 'L' THEN 'Low'
    WHEN ORDER_PRIORITY = 'M' THEN 'Medium'
    WHEN ORDER_PRIORITY = 'H' THEN 'High'
    WHEN ORDER_PRIORITY = 'C' THEN 'Critical'
END;

-- Step 10: Query Total Orders in the ASIA Region
SELECT COUNT(*) AS TOTAL_ORDERS
FROM SALES_DATA
WHERE REGION = 'ASIA';

-- Step 11-12: Analyze Query Pattern Before Clustering
SELECT COUNT(*) AS TOTAL_ORDERS
FROM SALES_DATA
WHERE REGION = 'ASIA';

-- Step 13: Cluster SALES_DATA Table
ALTER TABLE SALES_DATA CLUSTER BY (REGION);

-- Step 14: Re-run Query After Clustering
SELECT COUNT(*) AS TOTAL_ORDERS
FROM SALES_DATA
WHERE REGION = 'ASIA';

-- Step 15: Create Task to Load SALES_DATA Every Hour Except Sunday
CREATE OR REPLACE TASK LOAD_SALES_DATA_TASK
WAREHOUSE = LOAD_WH
SCHEDULE = 'USING CRON 0 * * * * UTC' -- Every hour except Sunday
AS
INSERT INTO SALES_DATA
SELECT *
FROM SOURCE_TABLE
WHERE EXTRACT(DAYOFWEEK FROM CURRENT_DATE) != 1;

-- Step 16: Create Task to Load AGG_SALES_BY_COUNTRY Twice a Week
CREATE OR REPLACE TASK LOAD_AGG_SALES_TASK
WAREHOUSE = LOAD_WH
SCHEDULE = 'USING CRON 30 22 * * 1,4 UTC' -- 4am IST Monday and Thursday
AS
INSERT INTO AGG_SALES_BY_COUNTRY
SELECT REGION, COUNTRY, SUM(TOTAL_PROFIT)
FROM SALES_DATA
GROUP BY REGION, COUNTRY;

-- Step 17: Create Reader Accounts
CREATE OR REPLACE ACCOUNT READER_IND;
CREATE OR REPLACE ACCOUNT READER_GERMANY;

-- Step 18: Share SALES_DATA with Reader Accounts
CREATE OR REPLACE SHARE INDIAN_SALES_SHARE;
ADD TABLE SALES_DATA;
GRANT USAGE ON SHARE INDIAN_SALES_SHARE TO READER_IND;

CREATE OR REPLACE SHARE GERMAN_SALES_SHARE;
ADD TABLE SALES_DATA;
GRANT USAGE ON SHARE GERMAN_SALES_SHARE TO READER_GERMANY;
