-- ============================================================
--  10_MultiITPIC_fix.sql
--  Fix sp_CloseITPICTask:
--  ปัญหา: Active count เช็คไม่ถูก → Status เปลี่ยนเร็วเกินไป
--  Fix:   เช็ค Active count ก่อน UPDATE + ใช้ COLLATE
-- ============================================================

USE [BTITTicketReq]
GO

CREATE OR ALTER PROCEDURE dbo.sp_CloseITPICTask
    @TicketId   UNIQUEIDENTIFIER,
    @SamAcc     NVARCHAR(100),
    @Remark     NVARCHAR(1000) = NULL,
    @NewStatus  NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    BEGIN TRY

        -- ตรวจสอบว่า PIC นี้ยัง Active อยู่จริง
        IF NOT EXISTS (
            SELECT 1 FROM dbo.TBITTicketPIC
            WHERE TicketId = @TicketId
              AND SamAcc   = @SamAcc COLLATE THAI_CI_AS
              AND Status   = 'Active'
        )
        BEGIN
            -- ปิดไปแล้ว หรือไม่มีสิทธิ์
            SET @NewStatus = 'PendingITPIC';
            COMMIT TRANSACTION;
            RETURN;
        END

        -- Mark PIC นี้ว่า Closed
        UPDATE dbo.TBITTicketPIC
        SET    Status      = 'Closed',
               ClosedAt    = GETDATE(),
               ClosedBy    = @SamAcc,
               CloseRemark = @Remark
        WHERE  TicketId = @TicketId
          AND  SamAcc   = @SamAcc COLLATE THAI_CI_AS
          AND  Status   = 'Active';

        -- Log
        INSERT INTO dbo.TBITTicketLog
               (TicketId, ApproverFunCode, ApproverSam, ApproverName,
                Action, Remark, ActionAt)
        SELECT  @TicketId, 6, @SamAcc,
                ISNULL(e.DISPNAME, @SamAcc), 'CloseTask', @Remark, GETDATE()
        FROM   [BT_HR].[dbo].[onl_TBADUsers] e
        WHERE  e.SAMACC = @SamAcc COLLATE THAI_CI_AS AND e.empstatus = 1;

        -- นับ PIC ที่ยัง Active หลัง UPDATE
        DECLARE @ActiveCount INT;
        SELECT @ActiveCount = COUNT(*)
        FROM   dbo.TBITTicketPIC
        WHERE  TicketId = @TicketId
          AND  Status   = 'Active';

        IF @ActiveCount = 0
        BEGIN
            -- ทุกคน Close แล้ว → ส่งต่อให้ IT Admin
            SET @NewStatus = 'PendingITAdminClose';
            UPDATE dbo.TBITTicket
            SET    Status    = 'PendingITAdminClose',
                   UpdatedAt = GETDATE()
            WHERE  TicketId  = @TicketId;
        END
        ELSE
        BEGIN
            -- ยังมีคนที่ยังไม่ Close → คงสถานะ PendingITPIC
            SET @NewStatus = 'PendingITPIC';
            UPDATE dbo.TBITTicket
            SET    Status    = 'PendingITPIC',
                   UpdatedAt = GETDATE()
            WHERE  TicketId  = @TicketId;
        END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
PRINT 'sp_CloseITPICTask fixed.'
GO

-- ── Fix data: Reset Ticket ที่มี Active PIC แต่ Status ผิด ───────────
-- รัน script นี้เพื่อแก้ data ที่ผิดพลาดแล้ว
UPDATE t
SET    t.Status    = 'PendingITPIC',
       t.UpdatedAt = GETDATE()
FROM   dbo.TBITTicket t
WHERE  t.Status = 'PendingITAdminClose'
  AND  EXISTS (
       SELECT 1 FROM dbo.TBITTicketPIC p
       WHERE  p.TicketId = t.TicketId
         AND  p.Status   = 'Active'
  );

PRINT CONCAT('Fixed ', @@ROWCOUNT, ' ticket(s) with wrong status.');
GO
