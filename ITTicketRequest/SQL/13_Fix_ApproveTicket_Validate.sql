-- ============================================================
--  13_Fix_ApproveTicket_Validate.sql
--  Bug: Multi-Role User (DeptMgr+ITMgr) สามารถ Approve
--       IT Manager step แทน IT Manager ที่ถูกกำหนดได้
--  Fix: Validate Approver ก่อน Approve ทุก Step
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_ApproveTicket
    @TicketId     UNIQUEIDENTIFIER,
    @ApproverSam  NVARCHAR(100),
    @ApproverName NVARCHAR(255),
    @Action       NVARCHAR(20),
    @Remark       NVARCHAR(1000) = NULL,
    @AssignTo     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        DECLARE @CurrentStatus   NVARCHAR(50);
        DECLARE @ReqVPN          BIT;
        DECLARE @ApproverFunCode INT;
        DECLARE @ApprDeptManager NVARCHAR(100);
        DECLARE @ApprManagingDir NVARCHAR(100);
        DECLARE @ApprITManager   NVARCHAR(100);

        SELECT
            @CurrentStatus   = Status,
            @ReqVPN          = ReqVPN,
            @ApprDeptManager = ApprDeptManager,
            @ApprManagingDir = ApprManagingDir,
            @ApprITManager   = ApprITManager
        FROM dbo.TBITTicket
        WHERE TicketId = @TicketId;

        SET @ApproverFunCode = CASE @CurrentStatus
            WHEN 'PendingDeptMgr'       THEN 8
            WHEN 'PendingManagingDir'   THEN 4
            WHEN 'PendingITMgr'         THEN 7
            WHEN 'PendingITAdminAssign' THEN 5
            WHEN 'PendingITPIC'         THEN 6
            WHEN 'PendingITAdminClose'  THEN 9
            ELSE 0
        END;

        -- ════════════════════════════════════════════════════════
        --  VALIDATE: ตรวจ Approver ตรงกับที่ Designate ไว้
        -- ════════════════════════════════════════════════════════
        IF @Action IN ('Approve', 'Reject')
        BEGIN
            -- DeptMgr Step
            IF @CurrentStatus = 'PendingDeptMgr'
               AND @ApprDeptManager IS NOT NULL
               AND @ApprDeptManager != @ApproverSam COLLATE THAI_CI_AS
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 'Error: You are not the designated Department Manager for this ticket' AS NewStatus;
                RETURN;
            END

            -- ManagingDir Step
            IF @CurrentStatus = 'PendingManagingDir'
               AND @ApprManagingDir IS NOT NULL
               AND @ApprManagingDir != @ApproverSam COLLATE THAI_CI_AS
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 'Error: You are not the designated Managing Director for this ticket' AS NewStatus;
                RETURN;
            END

            -- ITMgr Step ← แก้ Bug หลัก: Keatisak ไม่ควร Approve แทน Pannee
            IF @CurrentStatus = 'PendingITMgr'
               AND @ApprITManager IS NOT NULL
               AND @ApprITManager != @ApproverSam COLLATE THAI_CI_AS
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT 'Error: You are not the designated IT Manager for this ticket' AS NewStatus;
                RETURN;
            END
        END

        -- ── Log ──────────────────────────────────────────────────
        INSERT INTO dbo.TBITTicketLog
               (TicketId, ApproverFunCode, ApproverSam, ApproverName,
                Action, AssignedTo, Remark, ActionAt)
        VALUES (@TicketId, @ApproverFunCode, @ApproverSam, @ApproverName,
                @Action, @AssignTo, @Remark, GETDATE());

        -- ── Compute New Status ───────────────────────────────────
        DECLARE @NewStatus NVARCHAR(50);

        IF @Action = 'Reject'
            SET @NewStatus = 'Rejected';
        ELSE IF @Action = 'Assign'
        BEGIN
            SET @NewStatus = 'PendingITPIC';
            UPDATE dbo.TBITTicket
            SET    ApprITPIC   = @AssignTo,
                   ApprITAdmin = @ApproverSam
            WHERE  TicketId = @TicketId;
        END
        ELSE -- Approve
            SET @NewStatus = CASE @CurrentStatus
                WHEN 'PendingDeptMgr'
                    THEN CASE WHEN @ReqVPN = 1 THEN 'PendingManagingDir' ELSE 'PendingITMgr' END
                WHEN 'PendingManagingDir'   THEN 'PendingITMgr'
                WHEN 'PendingITMgr'         THEN 'PendingITAdminAssign'
                WHEN 'PendingITAdminAssign' THEN 'PendingITPIC'
                WHEN 'PendingITPIC'         THEN 'PendingITAdminClose'
                WHEN 'PendingITAdminClose'  THEN 'Completed'
                ELSE 'Completed'
            END;

        -- ── Update Ticket ────────────────────────────────────────
        UPDATE dbo.TBITTicket
        SET    Status      = @NewStatus,
               UpdatedAt   = GETDATE(),
               CompletedAt = CASE WHEN @NewStatus IN ('Completed','Rejected') THEN GETDATE() ELSE NULL END
        WHERE  TicketId = @TicketId;

        COMMIT TRANSACTION;
        SELECT @NewStatus AS NewStatus;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
PRINT 'sp_ApproveTicket updated — designated approver validation added.'
GO
PRINT '=== 13_Fix_ApproveTicket_Validate.sql completed ==='
GO
