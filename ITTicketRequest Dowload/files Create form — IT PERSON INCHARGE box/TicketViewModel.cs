namespace ITTicketRequest.Models
{
    // ════════════════════════════════════════════════════════════════
    //  TicketViewModel — Form สำหรับยื่นคำร้อง IT Ticket
    // ════════════════════════════════════════════════════════════════
    public class TicketViewModel
    {
        // ── Requester Info ───────────────────────────────────────────
        public string  SamAcc        { get; set; } = "";
        public string  RequesterName { get; set; } = "";
        public string  RequesterEmail{ get; set; } = "";
        public string  Department    { get; set; } = "";
        public string? Section       { get; set; }
        public string? Position      { get; set; }
        public string? Reason        { get; set; }

        // ── Request Types ────────────────────────────────────────────
        public bool   ReqComputer    { get; set; }
        public string? ComputerType  { get; set; }   // Laptop | Desktop
        public string? ComputerNote  { get; set; }

        public bool   ReqEmail       { get; set; }
        public string? EmailRequest  { get; set; }

        public bool   ReqNetwork     { get; set; }
        public List<NetworkDriveItem> NetworkDrives { get; set; } = new();

        public bool   ReqPrograms    { get; set; }
        public List<string> SelectedPrograms { get; set; } = new();
        public string? ProgramOther  { get; set; }

        public bool   ReqVPN         { get; set; }
        public string? VPNType       { get; set; }   // Permanent | Temporary
        public DateTime? VPNFrom     { get; set; }
        public DateTime? VPNTo       { get; set; }

        // ── Approvers (selected on form) ─────────────────────────────
        public string? ApprDeptManager   { get; set; }   // FUNCODE=8 (auto from HR)
        public string? ApprManagingDir   { get; set; }   // FUNCODE=4 (only if VPN)
        public string? ApprITManager     { get; set; }   // FUNCODE=7
        public string? ApprITPIC       { get; set; }   // FUNCODE=6 (IT Admin pre-selects on Create)
        // IT Admin (5) assigned during workflow
    }

    // ── Network Drive Item ────────────────────────────────────────────
    public class NetworkDriveItem
    {
        public string  Drive      { get; set; } = "";
        public bool    Read       { get; set; }
        public bool    Write      { get; set; }
        public string? CustomPath { get; set; }
    }
}
