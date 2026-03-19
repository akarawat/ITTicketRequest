-- ============================================================
--  00_CreateDatabase.sql
--  สร้างฐานข้อมูล BTITTicketReq และกำหนดสิทธิ์
--
--  ขั้นตอน:
--    1. รัน script นี้ใน context ของ [master]
--    2. รัน script 01~04 ต่อไปใน context ของ [BTITTicketReq]
--
--  หมายเหตุ:
--    - ใช้ DB User เดิมที่มีสิทธิ์เข้าถึง BT_HR อยู่แล้ว
--    - User นั้นต้องมี Login บน SQL Server แล้ว
--    - เปลี่ยน YOUR_LOGIN_NAME เป็น Login name จริง
-- ============================================================

USE [master]
GO

-- ── STEP 1: สร้างฐานข้อมูล BTITTicketReq ───────────────────────
IF NOT EXISTS (
    SELECT name FROM sys.databases WHERE name = N'BTITTicketReq'
)
BEGIN
    CREATE DATABASE [BTITTicketReq]
        COLLATE Thai_CI_AS;     -- ← ใช้ Collation เดียวกับ BTITReq
    PRINT 'Database [BTITTicketReq] created.'
END
ELSE
    PRINT 'Database [BTITTicketReq] already exists — skipped.'
GO

-- ── STEP 2: กำหนดสิทธิ์ db_owner ────────────────────────────────
-- เปลี่ยน 'YOUR_LOGIN_NAME' ให้ตรงกับ SQL Login ที่ใช้ใน Connection String
-- เช่น: sa, bt_app_user, BTITReqUser ฯลฯ

USE [BTITTicketReq]
GO

-- สร้าง User ใน DB ถ้ายังไม่มี
IF NOT EXISTS (
    SELECT name FROM sys.database_principals
    WHERE name = N'YOUR_LOGIN_NAME' AND type_desc = 'SQL_USER'
)
BEGIN
    CREATE USER [YOUR_LOGIN_NAME] FOR LOGIN [YOUR_LOGIN_NAME];
    PRINT 'User [YOUR_LOGIN_NAME] created in BTITTicketReq.'
END
ELSE
    PRINT 'User [YOUR_LOGIN_NAME] already exists — skipped.'
GO

-- กำหนด db_owner
ALTER ROLE [db_owner] ADD MEMBER [YOUR_LOGIN_NAME];
PRINT 'User [YOUR_LOGIN_NAME] assigned db_owner on BTITTicketReq.'
GO

-- ── STEP 3: ตรวจสอบ Cross-DB Access ไปยัง BT_HR ─────────────────
-- หาก User ใช้ Login เดิมที่มีสิทธิ์ BT_HR อยู่แล้ว
-- ไม่ต้องทำอะไรเพิ่ม — SQL Server ใช้ Login เดียวกันข้าม DB ได้

-- ตรวจสอบว่า Login มีสิทธิ์เข้า BT_HR ไหม:
USE [BT_HR]
GO
SELECT dp.name, dp.type_desc, rp.name AS role_name
FROM   sys.database_principals dp
LEFT JOIN sys.database_role_members rm  ON rm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals  rp  ON rp.principal_id = rm.role_principal_id
WHERE  dp.name = N'YOUR_LOGIN_NAME';
GO

-- ── ผลลัพธ์ที่คาดหวัง ─────────────────────────────────────────────
-- BTITTicketReq: YOUR_LOGIN_NAME มีสิทธิ์ db_owner
-- BT_HR:         YOUR_LOGIN_NAME มีสิทธิ์ db_datareader (อย่างน้อย)
-- ทั้งสอง DB อยู่บน Server เดียวกัน (BTDB04)
-- → Cross-DB JOIN [BTITTicketReq].[dbo].TBITTicket
--   JOIN [BT_HR].[dbo].onl_TBADUsers ทำได้ทันที
-- ============================================================

PRINT ''
PRINT '=== 00_CreateDatabase.sql completed ==='
PRINT 'Next: Run 01_CreateTables.sql on [BTITTicketReq]'
GO
