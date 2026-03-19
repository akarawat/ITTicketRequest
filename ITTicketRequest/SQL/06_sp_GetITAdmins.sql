-- ============================================================
--  06_sp_GetITAdmins.sql
--  ดึงรายชื่อ IT Admin (FUNCODE=5, FLAG=1) จาก BTITReq
--  สำหรับแสดงใน Create form — IT ADMIN → ASSIGN PIC box
--
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetITAdmins
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        f.USERLOGON          AS SamAcc,
        e.DISPNAME           AS DisplayName,
        ISNULL(e.UEMAIL, '') AS Email,
        ISNULL(e.DEPART, '') AS Department
    FROM   [BTITReq].[dbo].[TBUserFunction] f
    JOIN   [BT_HR].[dbo].[onl_TBADUsers]   e
           ON e.SAMACC = f.USERLOGON COLLATE THAI_CI_AS
    WHERE  f.FUNCODE   = 5       -- IT Admin / Staff
      AND  f.FLAG      = 1
      AND  e.empstatus = 1
    ORDER  BY e.DISPNAME;
END
GO

PRINT 'sp_GetITAdmins created — FUNCODE=5, FLAG=1'
GO

-- ── ทดสอบ ──────────────────────────────────────────────────────────
-- EXEC dbo.sp_GetITAdmins
GO
