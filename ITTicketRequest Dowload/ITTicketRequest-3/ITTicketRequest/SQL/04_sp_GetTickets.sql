-- ============================================================
--  04_sp_GetTickets.sql
-- ============================================================

USE [BTITReq]
GO

-- ── sp_GetTicketList ───────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_GetTicketList
    @SamAcc         NVARCHAR(100) = NULL,
    @Status         NVARCHAR(50)  = NULL,
    @FunCode        INT           = NULL,
    @ApproverSamAcc NVARCHAR(100) = NULL,
    @PageNo         INT           = 1,
    @PageSize       INT           = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PendingStatus NVARCHAR(50) = NULL;
    IF @FunCode IS NOT NULL
        SET @PendingStatus = CASE @FunCode
            WHEN 8 THEN 'PendingDeptMgr'
            WHEN 4 THEN 'PendingManagingDir'
            WHEN 7 THEN 'PendingITMgr'
            WHEN 5 THEN 'PendingITAdminAssign'   -- IT Admin: เลือก PIC
            WHEN 6 THEN 'PendingITPIC'            -- IT PIC: ดำเนินการ
            WHEN 9 THEN 'PendingITAdminClose'     -- IT Admin: ปิด Ticket
            ELSE NULL
        END;

    SELECT
        t.TicketId, t.DocNumber, t.RequesterName, t.RequesterEmail,
        t.Department, t.Status,
        t.ReqComputer, t.ReqEmail, t.ReqNetwork, t.ReqPrograms, t.ReqVPN,
        t.ApprITPIC, t.ApprITAdmin,
        t.CreatedAt, t.CompletedAt,
        CASE t.Status
            WHEN 'PendingDeptMgr'       THEN 'Pending Dept Manager'
            WHEN 'PendingManagingDir'   THEN 'Pending Managing Director'
            WHEN 'PendingITMgr'         THEN 'Pending IT Manager'
            WHEN 'PendingITAdminAssign' THEN 'Pending IT Admin (Assign PIC)'
            WHEN 'PendingITPIC'         THEN 'Pending IT PIC'
            WHEN 'PendingITAdminClose'  THEN 'Pending IT Admin (Close)'
            WHEN 'Completed'            THEN 'Completed'
            WHEN 'Rejected'             THEN 'Rejected'
            ELSE t.Status
        END AS StatusLabel,
        COUNT(*) OVER() AS TotalCount

    FROM dbo.TBITTicket t

    WHERE
        (@SamAcc IS NULL OR t.SamAcc = @SamAcc)
        AND (@Status IS NULL OR t.Status = @Status)
        AND (@PendingStatus IS NULL OR t.Status = @PendingStatus)
        AND (
            @ApproverSamAcc IS NULL
            OR @FunCode = 9
            OR (@FunCode = 8 AND (t.ApprDeptManager IS NULL OR t.ApprDeptManager = @ApproverSamAcc COLLATE THAI_CI_AS))
            OR (@FunCode = 4 AND (t.ApprManagingDir IS NULL OR t.ApprManagingDir = @ApproverSamAcc COLLATE THAI_CI_AS))
            OR (@FunCode = 7 AND (t.ApprITManager   IS NULL OR t.ApprITManager   = @ApproverSamAcc COLLATE THAI_CI_AS))
            -- IT Admin (5,9) เห็นทุก Ticket ที่อยู่ใน status ของตัวเอง
            OR  @FunCode = 5
        )

    ORDER BY t.CreatedAt DESC
    OFFSET (@PageNo - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ── sp_GetTicketById ───────────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_GetTicketById
    @TicketId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Main ticket data
    SELECT t.*, 
           e_dm.DISPNAME  AS DeptManagerName,
           e_md.DISPNAME  AS ManagingDirName,
           e_itm.DISPNAME AS ITManagerName,
           e_pic.DISPNAME AS ITPICName,
           e_itadm.DISPNAME AS ITAdminName
    FROM   dbo.TBITTicket t
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e_dm
           ON e_dm.SAMACC = t.ApprDeptManager COLLATE THAI_CI_AS
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e_md
           ON e_md.SAMACC = t.ApprManagingDir COLLATE THAI_CI_AS
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e_itm
           ON e_itm.SAMACC = t.ApprITManager COLLATE THAI_CI_AS
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e_pic
           ON e_pic.SAMACC = t.ApprITPIC COLLATE THAI_CI_AS
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e_itadm
           ON e_itadm.SAMACC = t.ApprITAdmin COLLATE THAI_CI_AS
    WHERE  t.TicketId = @TicketId;

    -- 2. Network Drives
    SELECT Drive, DriveRead, DriveWrite, CustomPath
    FROM   dbo.TBITTicketNetDrive
    WHERE  TicketId = @TicketId;

    -- 3. Programs
    SELECT ProgramName
    FROM   dbo.TBITTicketProgram
    WHERE  TicketId = @TicketId;

    -- 4. Approval Log
    SELECT l.*, e.DISPNAME AS ApproverDisplayName
    FROM   dbo.TBITTicketLog l
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] e
           ON e.SAMACC = l.ApproverSam COLLATE THAI_CI_AS
    WHERE  l.TicketId = @TicketId
    ORDER  BY l.ActionAt;
END
GO

PRINT 'sp_GetTicketList and sp_GetTicketById created.'
GO
