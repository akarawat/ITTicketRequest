-- ============================================================
--  05_sp_GetApprovers.sql
--  ดึงรายชื่อ Approver ตาม FUNCODE
--  Cross-DB: TBUserFunction อยู่ใน [BTITReq]
--            Employee info  อยู่ใน [BT_HR]
--
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetApprovers
    @FunCode INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        f.USERLOGON                                        AS SamAcc,
        e.DISPNAME                                         AS DisplayName,
        ISNULL(e.UEMAIL, '')                               AS Email,
        ISNULL(e.DEPART, '')                               AS Department
    FROM   [BTITReq].[dbo].[TBUserFunction] f              -- ← Cross-DB
    JOIN   [BT_HR].[dbo].[onl_TBADUsers]   e
           ON e.SAMACC = f.USERLOGON COLLATE THAI_CI_AS
    WHERE  f.FUNCODE   = @FunCode
      AND  f.FLAG      = 1
      AND  e.empstatus = 1
    ORDER  BY e.DISPNAME;
END
GO

PRINT 'sp_GetApprovers created — Cross-DB: BTITReq.TBUserFunction + BT_HR.onl_TBADUsers'
GO

-- ── ทดสอบ ──────────────────────────────────────────────────────────
-- EXEC dbo.sp_GetApprovers @FunCode = 4   -- Managing Director
-- EXEC dbo.sp_GetApprovers @FunCode = 5   -- IT Admin
-- EXEC dbo.sp_GetApprovers @FunCode = 6   -- IT PIC
-- EXEC dbo.sp_GetApprovers @FunCode = 7   -- IT Manager
-- EXEC dbo.sp_GetApprovers @FunCode = 8   -- Dept Manager
-- EXEC dbo.sp_GetApprovers @FunCode = 9   -- System Admin
GO
