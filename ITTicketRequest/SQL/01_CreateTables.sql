-- ============================================================
--  01_CreateTables.sql
--  สร้างตาราง ITTicketRequest บน DB: BTITReq
--  (ใช้ DB เดิม เพิ่ม Tables ใหม่)
-- ============================================================

USE [BTITReq]
GO

-- ── Main Ticket Table ─────────────────────────────────────────────
IF OBJECT_ID('dbo.TBITTicket','U') IS NULL
CREATE TABLE dbo.TBITTicket (
    TicketId        UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    DocNumber       NVARCHAR(30)     NOT NULL,
    SamAcc          NVARCHAR(100)    NOT NULL,
    RequesterName   NVARCHAR(255)    NOT NULL,
    RequesterEmail  NVARCHAR(255)    NOT NULL,
    Department      NVARCHAR(255)    NOT NULL,
    Section         NVARCHAR(255)    NULL,
    Position        NVARCHAR(255)    NULL,
    Reason          NVARCHAR(1000)   NULL,

    -- Request Types
    ReqComputer     BIT              NOT NULL DEFAULT 0,
    ComputerType    NVARCHAR(20)     NULL,
    ComputerNote    NVARCHAR(500)    NULL,
    ReqEmail        BIT              NOT NULL DEFAULT 0,
    EmailRequest    NVARCHAR(255)    NULL,
    ReqNetwork      BIT              NOT NULL DEFAULT 0,
    ReqPrograms     BIT              NOT NULL DEFAULT 0,
    ProgramOther    NVARCHAR(500)    NULL,
    ReqVPN          BIT              NOT NULL DEFAULT 0,
    VPNType         NVARCHAR(20)     NULL,
    VPNFrom         DATE             NULL,
    VPNTo           DATE             NULL,

    -- Assigned Approvers
    ApprDeptManager NVARCHAR(100)    NULL,   -- FUNCODE=8 (auto from HR)
    ApprManagingDir NVARCHAR(100)    NULL,   -- FUNCODE=4 (only if VPN)
    ApprITManager   NVARCHAR(100)    NULL,   -- FUNCODE=7
    ApprITAdmin     NVARCHAR(100)    NULL,   -- FUNCODE=5 (assigned during workflow)
    ApprITPIC       NVARCHAR(100)    NULL,   -- FUNCODE=6 (assigned by IT Admin)

    -- Status Flow:
    --   PendingDeptMgr → [VPN?]
    --     No  → PendingITMgr → PendingITAdminAssign → PendingITPIC → PendingITAdminClose → Completed
    --     Yes → PendingManagingDir → PendingITMgr → PendingITAdminAssign → PendingITPIC → PendingITAdminClose → Completed
    Status          NVARCHAR(50)     NOT NULL DEFAULT 'PendingDeptMgr',

    CreatedAt       DATETIME         NOT NULL DEFAULT GETDATE(),
    UpdatedAt       DATETIME         NOT NULL DEFAULT GETDATE(),
    CompletedAt     DATETIME         NULL
);
GO

-- ── Network Drives ────────────────────────────────────────────────
IF OBJECT_ID('dbo.TBITTicketNetDrive','U') IS NULL
CREATE TABLE dbo.TBITTicketNetDrive (
    Id         UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    TicketId   UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.TBITTicket(TicketId),
    Drive      NVARCHAR(10)     NOT NULL,
    DriveRead  BIT              NOT NULL DEFAULT 0,
    DriveWrite BIT              NOT NULL DEFAULT 0,
    CustomPath NVARCHAR(500)    NULL
);
GO

-- ── Programs ──────────────────────────────────────────────────────
IF OBJECT_ID('dbo.TBITTicketProgram','U') IS NULL
CREATE TABLE dbo.TBITTicketProgram (
    Id          UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    TicketId    UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.TBITTicket(TicketId),
    ProgramName NVARCHAR(255)    NOT NULL
);
GO

-- ── Approval Log ──────────────────────────────────────────────────
IF OBJECT_ID('dbo.TBITTicketLog','U') IS NULL
CREATE TABLE dbo.TBITTicketLog (
    LogId           UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    TicketId        UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.TBITTicket(TicketId),
    ApproverFunCode INT              NOT NULL,
    ApproverSam     NVARCHAR(100)    NOT NULL,
    ApproverName    NVARCHAR(255)    NULL,
    Action          NVARCHAR(20)     NOT NULL,   -- Approve | Reject | Assign
    AssignedTo      NVARCHAR(100)    NULL,        -- เมื่อ IT Admin Assign PIC
    Remark          NVARCHAR(1000)   NULL,
    ActionAt        DATETIME         NOT NULL DEFAULT GETDATE()
);
GO

-- ── Document Sequence (ใช้ร่วมกับ BTITReq ได้ หรือแยก prefix) ────
IF OBJECT_ID('dbo.TBTicketDocSequence','U') IS NULL
CREATE TABLE dbo.TBTicketDocSequence (
    SeqYear CHAR(4)  NOT NULL PRIMARY KEY,
    LastSeq INT      NOT NULL DEFAULT 0
);
GO

PRINT '01_CreateTables.sql completed.'
GO
