namespace ITTicketRequest.Models
{
    // ── AppSettings ────────────────────────────────────────────────────
    public class AppSettingsModel
    {
        public string AuthenUrl   { get; set; } = "";
        public string URLSITE     { get; set; } = "";
        public string EmailSender { get; set; } = "";
        public string MailForm    { get; set; } = "";
        public string MailDebug   { get; set; } = "1";
    }

    // ── UserSessionModel ───────────────────────────────────────────────
    // FUNCODE mapping (TBUserFunction):
    //   1 = Requester (auto)
    //   4 = Managing Director
    //   5 = IT Admin / Staff
    //   6 = IT Person Incharge (IT PIC)
    //   7 = IT Manager
    //   8 = Department Manager
    //   9 = System Admin
    public class UserSessionModel
    {
        // SSO fields
        public string Id         { get; set; } = "";
        public string UserLogon  { get; set; } = "";
        public string SamAcc     { get; set; } = "";
        public string Email      { get; set; } = "";
        public string FullName   { get; set; } = "";
        public string Department { get; set; } = "";

        // Role flags (loaded from TBUserFunction)
        public bool IsAdmin          { get; set; }   // FUNCODE=9
        public bool IsDeptManager    { get; set; }   // FUNCODE=8
        public bool IsManagingDirector { get; set; } // FUNCODE=4
        public bool IsITManager      { get; set; }   // FUNCODE=7
        public bool IsITPIC          { get; set; }   // FUNCODE=6
        public bool IsITAdmin        { get; set; }   // FUNCODE=5
        public bool IsUser           { get; set; } = true;

        // Convenience
        public bool IsAnyApprover => IsAdmin || IsDeptManager || IsManagingDirector
                                  || IsITManager || IsITPIC || IsITAdmin;

        public static string ParseSamAcc(string userLogon)
        {
            if (string.IsNullOrEmpty(userLogon)) return "";
            var parts = userLogon.Split('\\');
            return (parts.Length > 1 ? parts[1] : parts[0]).ToLower();
        }
    }

    // ── Approve Request ────────────────────────────────────────────────
    public class ApproveRequest
    {
        public Guid    RequestId { get; set; }
        public string  Action   { get; set; } = "";   // Approve | Reject
        public string? Remark   { get; set; }
        public string? AssignTo { get; set; }          // สำหรับ IT Admin Assign PIC
    }
}
