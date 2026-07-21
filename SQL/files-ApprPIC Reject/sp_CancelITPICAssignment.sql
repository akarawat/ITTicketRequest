/* ═══════════════════════════════════════════════════════════════════
   sp_CancelITPICAssignment
   ─────────────────────────────────────────────────────────────────
   วัตถุประสงค์:
     ให้ IT Admin ยกเลิกการ Assign PIC ของ Ticket ที่ Status = 'PendingITPIC'
     โดยไม่ต้องให้ IT Manager อนุมัติซ้ำ — กลับไปที่ 'PendingITAdminAssign'

   Input:
     @TicketId   UNIQUEIDENTIFIER  — Ticket ที่จะยกเลิก
     @SamAcc     NVARCHAR(50)      — SamAcc ของ IT Admin ที่กด Cancel
     @Remark     NVARCHAR(500)     — เหตุผลการยกเลิก (บังคับ)

   Output:
     @NewStatus  NVARCHAR(50)      — Status ใหม่หลัง Cancel

   Deploy:
     รันสคริปต์นี้ที่ Database [BTITTicketReq] โดยตรง
     ตรวจสอบชื่อตาราง Log ให้ตรงกับที่ใช้จริงในระบบก่อน Deploy
     (สคริปต์นี้อ้างอิงชื่อ TBITTicketLog และ TBITTicketPIC ตาม pattern
      ที่ sp_AssignITPIC / sp_ReturnITPICTask ใช้อยู่ — โปรดตรวจสอบให้ตรง
      กับชื่อจริงในระบบของท่านก่อนรัน)
   ═══════════════════════════════════════════════════════════════════ */

USE [BTITTicketReq]
GO

IF OBJECT_ID('dbo.sp_CancelITPICAssignment', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CancelITPICAssignment
GO

CREATE PROCEDURE dbo.sp_CancelITPICAssignment
    @TicketId   UNIQUEIDENTIFIER,
    @SamAcc     NVARCHAR(50),
    @Remark     NVARCHAR(500),
    @NewStatus  NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @CurrentStatus NVARCHAR(50);

        SELECT @CurrentStatus = Status
        FROM dbo.TBITTicket WITH (UPDLOCK, ROWLOCK)
        WHERE TicketId = @TicketId;

        IF @CurrentStatus IS NULL
        BEGIN
            RAISERROR('Ticket not found', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- ── Guard: อนุญาตยกเลิกเฉพาะตอน Status = PendingITPIC เท่านั้น ──
        IF @CurrentStatus <> 'PendingITPIC'
        BEGIN
            RAISERROR('Cannot cancel: ticket is not in PendingITPIC status (current: %s)', 16, 1, @CurrentStatus);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- 1) ยกเลิก PIC ที่ Active ทั้งหมดของ Ticket นี้
        UPDATE dbo.TBITTicketPIC
        SET Status = 'Cancelled'
        WHERE TicketId = @TicketId
          AND Status = 'Active';

        -- 2) เปลี่ยน Status ของ Ticket กลับไปที่ PendingITAdminAssign
        SET @NewStatus = 'PendingITAdminAssign';

        UPDATE dbo.TBITTicket
        SET Status    = @NewStatus,
            UpdatedAt = GETDATE()
        WHERE TicketId = @TicketId;

        -- 3) บันทึก Log การยกเลิก (FunCode = 9 = IT Admin)
        INSERT INTO dbo.TBITTicketLog
            (TicketId, ApproverFunCode, ApproverSam, Action, AssignedTo, Remark, ActionAt)
        VALUES
            (@TicketId, 9, @SamAcc, 'CancelAssignment', NULL, @Remark, GETDATE());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
