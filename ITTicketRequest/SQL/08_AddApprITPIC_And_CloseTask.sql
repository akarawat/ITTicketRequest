-- ============================================================
--  08_AddApprITPIC_And_CloseTask.sql
--  1. อัปเดต sp_InsertTicket — รับ @ApprITPIC ตั้งแต่ตอน Create
--     (IT Admin เลือก IT PIC ก่อน Submit)
--  2. sp_ApproveTicket — เพิ่ม 'CloseTask' action สำหรับ IT PIC
--
--  รัน script นี้บน DB: BTITTicketReq
-- ============================================================

USE [BTITTicketReq]
GO

-- ════════════════════════════════════════════════════════════════
--  STEP 1: อัปเดต sp_InsertTicket — เพิ่ม @ApprITPIC
-- ════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.sp_InsertTicket
    @SamAcc          NVARCHAR(100),
    @RequesterName   NVARCHAR(255),
    @Email           NVARCHAR(255),
    @Department      NVARCHAR(255),
    @Section         NVARCHAR(255)  = NULL,
    @Position        NVARCHAR(255)  = NULL,
    @Reason          NVARCHAR(1000) = NULL,
    @ReqComputer     BIT = 0,
    @ComputerType    NVARCHAR(20)   = NULL,
    @ComputerNote    NVARCHAR(500)  = NULL,
    @ReqEmail        BIT = 0,
    @EmailRequest    NVARCHAR(255)  = NULL,
    @NetworkDrives   NVARCHAR(MAX)  = NULL,
    @Programs        NVARCHAR(MAX)  = NULL,
    @ProgramOther    NVARCHAR(500)  = NULL,
    @ReqVPN          BIT = 0,
    @VPNType         NVARCHAR(20)   = NULL,
    @VPNFrom         DATE = NULL,
    @VPNTo           DATE = NULL,
    @ApprDeptManager NVARCHAR(100)  = NULL,
    @ApprManagingDir NVARCHAR(100)  = NULL,
    @ApprITManager   NVARCHAR(100)  = NULL,
    @ApprITPIC       NVARCHAR(100)  = NULL,   -- ← ใหม่: IT Admin เลือกก่อน Submit
    @NewTicketId     UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        SET @NewTicketId = NEWID();
        DECLARE @Year   CHAR(4) = CAST(YEAR(GETDATE()) AS CHAR(4));
        DECLARE @SeqNum INT;

        EXEC dbo.sp_GetNextTicketSeq @Year = @Year, @NextSeq = @SeqNum OUTPUT;

        DECLARE @DocNum NVARCHAR(30) =
            'TKT-' + @Year + '-' + RIGHT('0000' + CAST(@SeqNum AS VARCHAR), 4);

        INSERT INTO dbo.TBITTicket (
            TicketId, DocNumber, SamAcc, RequesterName, RequesterEmail,
            Department, Section, Position, Reason,
            ReqComputer, ComputerType, ComputerNote,
            ReqEmail, EmailRequest, ReqNetwork, ReqPrograms, ProgramOther,
            ReqVPN, VPNType, VPNFrom, VPNTo,
            ApprDeptManager, ApprManagingDir, ApprITManager, ApprITPIC,
            Status, CreatedAt, UpdatedAt
        )
        VALUES (
            @NewTicketId, @DocNum, @SamAcc, @RequesterName, @Email,
            @Department, @Section, @Position, @Reason,
            @ReqComputer, @ComputerType, @ComputerNote,
            @ReqEmail, @EmailRequest,
            CASE WHEN @NetworkDrives IS NOT NULL AND LEN(@NetworkDrives) > 2 THEN 1 ELSE 0 END,
            CASE WHEN @Programs      IS NOT NULL AND LEN(@Programs)      > 2 THEN 1 ELSE 0 END,
            @ProgramOther,
            @ReqVPN, @VPNType, @VPNFrom, @VPNTo,
            @ApprDeptManager, @ApprManagingDir, @ApprITManager, @ApprITPIC,
            'PendingDeptMgr', GETDATE(), GETDATE()
        );

        -- Insert Network Drives
        IF @NetworkDrives IS NOT NULL AND LEN(@NetworkDrives) > 2
            INSERT INTO dbo.TBITTicketNetDrive (TicketId, Drive, DriveRead, DriveWrite, CustomPath)
            SELECT @NewTicketId, Drive,
                   CASE WHEN DriveRead  IN ('true','1') THEN 1 ELSE 0 END,
                   CASE WHEN DriveWrite IN ('true','1') THEN 1 ELSE 0 END,
                   CustomPath
            FROM OPENJSON(@NetworkDrives)
            WITH (Drive NVARCHAR(10) '$.Drive', DriveRead NVARCHAR(10) '$.Read',
                  DriveWrite NVARCHAR(10) '$.Write', CustomPath NVARCHAR(500) '$.CustomPath')
            WHERE DriveRead IN ('true','1') OR DriveWrite IN ('true','1')
               OR (Drive = 'Other' AND CustomPath IS NOT NULL);

        -- Insert Programs
        IF @Programs IS NOT NULL AND LEN(@Programs) > 2
            INSERT INTO dbo.TBITTicketProgram (TicketId, ProgramName)
            SELECT @NewTicketId, [value]
            FROM OPENJSON(@Programs)
            WHERE [value] IS NOT NULL AND LEN([value]) > 0;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
PRINT 'sp_InsertTicket updated — @ApprITPIC added.'
GO

-- ════════════════════════════════════════════════════════════════
--  STEP 2: อัปเดต sp_ApproveTicket — เพิ่ม 'CloseTask' action
--  IT PIC กด Close Task → Status = PendingITAdminClose
-- ════════════════════════════════════════════════════════════════
CREATE OR ALTER PROCEDURE dbo.sp_ApproveTicket
    @TicketId     UNIQUEIDENTIFIER,
    @ApproverSam  NVARCHAR(100),
    @ApproverName NVARCHAR(255),
    @Action       NVARCHAR(20),    -- Approve | Reject | Assign | CloseTask
    @Remark       NVARCHAR(1000) = NULL,
    @AssignTo     NVARCHAR(100)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        DECLARE @CurrentStatus   NVARCHAR(50);
        DECLARE @ReqVPN          BIT;
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
            WHEN 'PendingITPIC'        THEN 6   -- IT PIC ทำงานและ CloseTask
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
            -- IT Admin เลือก PIC (จาก Pending page)
            SET @NewStatus = 'PendingITPIC';
            UPDATE dbo.TBITTicket
            SET    ApprITPIC   = @AssignTo,
                   ApprITAdmin = @ApproverSam
            WHERE  TicketId    = @TicketId;
        END
        ELSE IF @Action = 'CloseTask'
        BEGIN
            -- IT PIC ทำงานเสร็จ → ส่งกลับให้ IT Admin Close Ticket
            SET @NewStatus = 'PendingITAdminClose';
        END
        ELSE -- Approve
        BEGIN
            SET @NewStatus = CASE @CurrentStatus
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
PRINT 'sp_ApproveTicket updated — CloseTask action added.'
GO

PRINT '=== 08_AddApprITPIC_And_CloseTask.sql completed ==='
GO
