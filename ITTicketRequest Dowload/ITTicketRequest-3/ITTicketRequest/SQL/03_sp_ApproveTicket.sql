-- ============================================================
--  03_sp_ApproveTicket.sql
--  Approval Flow ใหม่:
--
--  PendingDeptMgr
--    └─ Approve → [ReqVPN?]
--         No  → PendingITMgr
--         Yes → PendingManagingDir → PendingITMgr
--    └─ Reject → Rejected
--
--  PendingManagingDir → Approve → PendingITMgr
--  PendingITMgr       → Approve → PendingITAdminAssign (IT Admin เลือก PIC)
--  PendingITAdminAssign → Assign → PendingITPIC (บันทึก ApprITPIC)
--  PendingITPIC       → Approve → PendingITAdminClose
--  PendingITAdminClose → Approve → Completed
-- ============================================================

USE [BTITReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_ApproveTicket
    @TicketId    UNIQUEIDENTIFIER,
    @ApproverSam NVARCHAR(100),
    @ApproverName NVARCHAR(255),
    @Action      NVARCHAR(20),    -- Approve | Reject | Assign
    @Remark      NVARCHAR(1000) = NULL,
    @AssignTo    NVARCHAR(100)  = NULL   -- SAM ของ IT PIC (เมื่อ IT Admin Assign)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        DECLARE @CurrentStatus NVARCHAR(50);
        DECLARE @ReqVPN        BIT;
        DECLARE @ApproverFunCode INT;

        SELECT @CurrentStatus = Status,
               @ReqVPN        = ReqVPN
        FROM   dbo.TBITTicket
        WHERE  TicketId = @TicketId;

        SET @ApproverFunCode = CASE @CurrentStatus
            WHEN 'PendingDeptMgr'      THEN 8
            WHEN 'PendingManagingDir'  THEN 4
            WHEN 'PendingITMgr'        THEN 7
            WHEN 'PendingITAdminAssign'THEN 5
            WHEN 'PendingITPIC'        THEN 6
            WHEN 'PendingITAdminClose' THEN 9
            ELSE 0
        END;

        -- ── Log ──────────────────────────────────────────────────────
        INSERT INTO dbo.TBITTicketLog
               (TicketId, ApproverFunCode, ApproverSam, ApproverName,
                Action, AssignedTo, Remark, ActionAt)
        VALUES (@TicketId, @ApproverFunCode, @ApproverSam, @ApproverName,
                @Action, @AssignTo, @Remark, GETDATE());

        -- ── Compute New Status ────────────────────────────────────────
        DECLARE @NewStatus NVARCHAR(50);

        IF @Action = 'Reject'
        BEGIN
            SET @NewStatus = 'Rejected';
        END
        ELSE IF @Action = 'Assign'
        BEGIN
            -- IT Admin (5) เลือก PIC → บันทึก ApprITPIC, เปลี่ยน Status
            SET @NewStatus = 'PendingITPIC';
            UPDATE dbo.TBITTicket
            SET    ApprITPIC  = @AssignTo,
                   ApprITAdmin = @ApproverSam
            WHERE  TicketId   = @TicketId;
        END
        ELSE -- Approve
        BEGIN
            SET @NewStatus = CASE @CurrentStatus
                -- DeptMgr → ถ้า VPN ไป ManagingDir, ถ้าไม่ → ITMgr
                WHEN 'PendingDeptMgr'
                    THEN CASE WHEN @ReqVPN = 1 THEN 'PendingManagingDir' ELSE 'PendingITMgr' END
                WHEN 'PendingManagingDir'  THEN 'PendingITMgr'
                WHEN 'PendingITMgr'        THEN 'PendingITAdminAssign'
                WHEN 'PendingITAdminAssign'THEN 'PendingITPIC'
                WHEN 'PendingITPIC'        THEN 'PendingITAdminClose'
                WHEN 'PendingITAdminClose' THEN 'Completed'
                ELSE 'Completed'
            END;
        END

        -- ── Update Ticket ─────────────────────────────────────────────
        UPDATE dbo.TBITTicket
        SET    Status      = @NewStatus,
               UpdatedAt   = GETDATE(),
               CompletedAt = CASE WHEN @NewStatus IN ('Completed','Rejected')
                                  THEN GETDATE() ELSE NULL END
        WHERE  TicketId    = @TicketId;

        COMMIT TRANSACTION;

        SELECT @NewStatus AS NewStatus;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT 'sp_ApproveTicket created.'
GO
