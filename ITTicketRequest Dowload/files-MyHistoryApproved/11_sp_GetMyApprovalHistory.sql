-- ============================================================
--  11_sp_GetMyApprovalHistory.sql
--  ดึงประวัติการ Approve/Action ของ User แต่ละคน
--  เห็นเฉพาะ Action ที่ตัวเองทำ — ไม่ปนกับคนอื่น
--
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetMyApprovalHistory
    @ApproverSam  NVARCHAR(100),
    @Action       NVARCHAR(20)  = NULL,   -- NULL=ทั้งหมด | Approve | Reject | Assign | CloseTask
    @DateFrom     DATE          = NULL,
    @DateTo       DATE          = NULL,
    @PageNo       INT           = 1,
    @PageSize     INT           = 20
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        -- Ticket info
        t.TicketId,
        t.DocNumber,
        t.RequesterName,
        t.RequesterEmail,
        t.Department,
        t.Status,
        t.CreatedAt                                         AS TicketCreatedAt,
        t.CompletedAt,

        -- Log info (เฉพาะ Action ของ @ApproverSam)
        l.LogId,
        l.Action,
        l.Remark,
        l.AssignedTo,
        l.ActionAt,
        l.ApproverFunCode,

        -- Assigned PIC name (กรณี Assign)
        pic.DISPNAME                                        AS AssignedToName,

        -- Status label
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

        -- Action label
        CASE l.Action
            WHEN 'Approve'   THEN 'Approved'
            WHEN 'Reject'    THEN 'Rejected'
            WHEN 'Assign'    THEN 'Assigned PIC'
            WHEN 'CloseTask' THEN 'Closed Task'
            ELSE l.Action
        END AS ActionLabel,

        -- Role name
        CASE l.ApproverFunCode
            WHEN 4 THEN 'Managing Director'
            WHEN 5 THEN 'IT Admin'
            WHEN 6 THEN 'IT PIC'
            WHEN 7 THEN 'IT Manager'
            WHEN 8 THEN 'Dept Manager'
            WHEN 9 THEN 'System Admin'
            ELSE 'User'
        END AS RoleName,

        COUNT(*) OVER() AS TotalCount

    FROM dbo.TBITTicketLog    l
    JOIN dbo.TBITTicket        t  ON t.TicketId  = l.TicketId
    LEFT JOIN [BT_HR].[dbo].[onl_TBADUsers] pic
                                  ON pic.SAMACC  = l.AssignedTo COLLATE THAI_CI_AS

    WHERE
        l.ApproverSam = @ApproverSam  COLLATE THAI_CI_AS
        AND (@Action   IS NULL OR l.Action  = @Action)
        AND (@DateFrom IS NULL OR CAST(l.ActionAt AS DATE) >= @DateFrom)
        AND (@DateTo   IS NULL OR CAST(l.ActionAt AS DATE) <= @DateTo)

    ORDER BY l.ActionAt DESC
    OFFSET (@PageNo - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

PRINT 'sp_GetMyApprovalHistory created.'
GO

-- ── ทดสอบ ──────────────────────────────────────────────────────────
-- EXEC dbo.sp_GetMyApprovalHistory @ApproverSam = 'jirawat.k'
-- EXEC dbo.sp_GetMyApprovalHistory @ApproverSam = 'Saowanee.S', @Action = 'Approve'
GO
