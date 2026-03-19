-- ============================================================
--  07_sp_UserRightsManagement.sql
--  User Rights Management SPs สำหรับ ITTicketRequest
--
--  Cross-DB:
--    TBUserFunction อยู่ใน [BTITReq] (shared กับ BTITReq)
--    Employee info  อยู่ใน [BT_HR]
--    Log table      อยู่ใน [BTITTicketReq] (แยกเป็นของตัวเอง)
--
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

-- ── Log Table ─────────────────────────────────────────────────────
IF OBJECT_ID('dbo.TBUserFunctionLog','U') IS NULL
CREATE TABLE dbo.TBUserFunctionLog (
    LogId     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    UserLogon NVARCHAR(100)    NOT NULL,
    FunCode   INT              NOT NULL,
    Action    NVARCHAR(20)     NOT NULL,   -- Grant | Revoke
    UpdatedBy NVARCHAR(100)    NOT NULL,
    UpdatedAt DATETIME         NOT NULL DEFAULT GETDATE()
);
GO
PRINT 'TBUserFunctionLog table ready.'
GO

-- ════════════════════════════════════════════════════════════════
--  sp_GetUserFunctions
--  ดึงรายชื่อพนักงานพร้อมสิทธิ์ทุก FUNCODE
--  Cross-DB: อ่าน TBUserFunction จาก [BTITReq]
-- ════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.sp_GetUserFunctions
    @Search     NVARCHAR(200) = NULL,
    @Department NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Result 1: Users + Roles ───────────────────────────────────
    SELECT
        e.SAMACC                                                    AS SamAcc,
        e.DISPNAME                                                  AS DisplayName,
        e.DISPNAME                                                  AS DisplayNameTH,
        ISNULL(e.UEMAIL,'')                                         AS Email,
        ISNULL(e.DEPART,'')                                         AS Department,
        ISNULL(e.DESCRIP,'')                                       AS Position,
        -- FUNCODE=1  Requester (auto)
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=1 AND FLAG=1), 0)                     AS HasRequester,
        -- FUNCODE=8  Dept Manager
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=8 AND FLAG=1), 0)                     AS HasDeptManager,
        -- FUNCODE=6  IT PIC
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=6 AND FLAG=1), 0)                     AS HasCrossDept,
        -- FUNCODE=7  IT Manager
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=7 AND FLAG=1), 0)                     AS HasITManager,
        -- FUNCODE=5  IT Admin / Staff
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=5 AND FLAG=1), 0)                     AS HasNetworkAdmin,
        -- FUNCODE=4  Managing Director
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=4 AND FLAG=1), 0)                     AS HasManagingDirector,
        -- FUNCODE=9  System Admin
        ISNULL((SELECT TOP 1 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = e.SAMACC COLLATE THAI_CI_AS
                  AND FUNCODE=9 AND FLAG=1), 0)                     AS HasSysAdmin

    FROM [BT_HR].[dbo].[onl_TBADUsers] e
    WHERE e.empstatus = 1
      AND (@Search     IS NULL
           OR e.DISPNAME LIKE '%' + @Search + '%'
           OR e.SAMACC  LIKE '%' + @Search + '%')
      AND (@Department IS NULL OR e.DEPART = @Department)
    ORDER BY e.DEPART, e.DISPNAME;

    -- ── Result 2: Department list ─────────────────────────────────
    SELECT DISTINCT DEPART
    FROM  [BT_HR].[dbo].[onl_TBADUsers]
    WHERE empstatus = 1 AND DEPART IS NOT NULL AND DEPART <> ''
    ORDER BY DEPART;
END
GO
PRINT 'sp_GetUserFunctions created.'
GO

-- ════════════════════════════════════════════════════════════════
--  sp_SetUserFunction
--  Grant / Revoke สิทธิ์ — เขียนไปยัง [BTITReq].TBUserFunction
--  พร้อม Log ใน [BTITTicketReq].TBUserFunctionLog
-- ════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.sp_SetUserFunction
    @UserLogon NVARCHAR(100),
    @FunCode   INT,
    @Action    NVARCHAR(20),    -- Grant | Revoke
    @UpdatedBy NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        IF @Action = 'Grant'
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM [BTITReq].[dbo].[TBUserFunction]
                WHERE USERLOGON = @UserLogon AND FUNCODE = @FunCode
            )
            BEGIN
                INSERT INTO [BTITReq].[dbo].[TBUserFunction]
                       (ID, USERLOGON, FUNCODE, FLAG)
                VALUES (NEWID(), @UserLogon, @FunCode, 1);
            END
            ELSE
            BEGIN
                UPDATE [BTITReq].[dbo].[TBUserFunction]
                SET    FLAG = 1
                WHERE  USERLOGON = @UserLogon AND FUNCODE = @FunCode;
            END
        END
        ELSE IF @Action = 'Revoke'
        BEGIN
            UPDATE [BTITReq].[dbo].[TBUserFunction]
            SET    FLAG = 0
            WHERE  USERLOGON = @UserLogon AND FUNCODE = @FunCode;
        END

        -- บันทึก Log
        INSERT INTO dbo.TBUserFunctionLog (UserLogon, FunCode, Action, UpdatedBy)
        VALUES (@UserLogon, @FunCode, @Action, @UpdatedBy);

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
PRINT 'sp_SetUserFunction created — writes to [BTITReq].[dbo].[TBUserFunction]'
GO

-- ════════════════════════════════════════════════════════════════
--  sp_GetUserFunctionLog
--  ดึงประวัติการเปลี่ยนสิทธิ์
-- ════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.sp_GetUserFunctionLog
    @UserLogon NVARCHAR(100) = NULL,
    @Top       INT           = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        l.UserLogon,
        l.FunCode,
        l.Action,
        l.UpdatedBy,
        l.UpdatedAt,
        CASE l.FunCode
            WHEN 1 THEN 'Requester'
            WHEN 4 THEN 'Managing Director'
            WHEN 5 THEN 'IT Admin / Staff'
            WHEN 6 THEN 'IT Person Incharge (IT PIC)'
            WHEN 7 THEN 'IT Manager'
            WHEN 8 THEN 'Department Manager'
            WHEN 9 THEN 'System Admin'
            ELSE 'FUNCODE=' + CAST(l.FunCode AS VARCHAR)
        END AS FunName
    FROM dbo.TBUserFunctionLog l
    WHERE (@UserLogon IS NULL OR l.UserLogon = @UserLogon)
    ORDER BY l.UpdatedAt DESC;
END
GO
PRINT 'sp_GetUserFunctionLog created.'
GO

PRINT '=== 07_sp_UserRightsManagement.sql completed ==='
GO
