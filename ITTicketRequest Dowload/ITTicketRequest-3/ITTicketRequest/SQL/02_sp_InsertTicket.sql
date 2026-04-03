-- ============================================================
--  02_sp_InsertTicket.sql
--  บันทึก Ticket ใหม่ + Running Number
-- ============================================================

USE [BTITReq]
GO

-- ── sp_GetNextTicketSeq (Thread-safe) ─────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_GetNextTicketSeq
    @Year    CHAR(4),
    @NextSeq INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.TBTicketDocSequence WHERE SeqYear = @Year)
        INSERT INTO dbo.TBTicketDocSequence (SeqYear, LastSeq) VALUES (@Year, 0);

    UPDATE dbo.TBTicketDocSequence
    SET    LastSeq  = LastSeq + 1,
           @NextSeq = LastSeq + 1
    WHERE  SeqYear  = @Year;
END
GO

-- ── sp_InsertTicket ────────────────────────────────────────────────
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

        -- กำหนด Status เริ่มต้น → เสมอเป็น PendingDeptMgr
        INSERT INTO dbo.TBITTicket (
            TicketId, DocNumber, SamAcc, RequesterName, RequesterEmail,
            Department, Section, Position, Reason,
            ReqComputer, ComputerType, ComputerNote,
            ReqEmail, EmailRequest, ReqNetwork, ReqPrograms, ProgramOther,
            ReqVPN, VPNType, VPNFrom, VPNTo,
            ApprDeptManager, ApprManagingDir, ApprITManager,
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
            @ApprDeptManager, @ApprManagingDir, @ApprITManager,
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

PRINT 'sp_InsertTicket created. Document format: TKT-YYYY-NNNN'
GO
