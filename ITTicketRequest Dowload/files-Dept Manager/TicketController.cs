using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Microsoft.Data.SqlClient;
using ITTicketRequest.Models;
using System.Text.Json;
using System.Data;

namespace ITTicketRequest.Controllers
{
    public class TicketController : Controller
    {
        private readonly IConfiguration  _config;
        private readonly AppSettingsModel _settings;
        private readonly IHttpClientFactory _http;

        public TicketController(IConfiguration config,
                                IOptions<AppSettingsModel> settings,
                                IHttpClientFactory http)
        {
            _config   = config;
            _settings = settings.Value;
            _http     = http;
        }

        private string LocalMailUrl =>
            $"{_config["TBCorApiServices:URLSITE"]}SendMail/MailSenderMessage";

        private UserSessionModel? GetSession()
        {
            var json = HttpContext.Session.GetString("UserSession");
            if (string.IsNullOrEmpty(json)) return null;
            return JsonSerializer.Deserialize<UserSessionModel>(json);
        }

        // ════════════════════════════════════════════════════════════
        //  VIEWS
        // ════════════════════════════════════════════════════════════

        // GET /Ticket/Create
        public IActionResult Create()
        {
            var session = GetSession();
            if (session == null) return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
            var vm = new TicketViewModel
            {
                RequesterName  = session.FullName,
                RequesterEmail = session.Email,
                Department     = session.Department,
                SamAcc         = session.SamAcc
            };
            return View(vm);
        }

        // POST /Ticket/Create
        [HttpPost, ValidateAntiForgeryToken]
        public IActionResult Create(TicketViewModel vm)
        {
            var session = GetSession();
            if (session == null) return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
            if (!ModelState.IsValid) return View(vm);

            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_InsertTicket", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SamAcc",          session.SamAcc);
                cmd.Parameters.AddWithValue("@RequesterName",   vm.RequesterName);
                cmd.Parameters.AddWithValue("@Email",           vm.RequesterEmail);
                cmd.Parameters.AddWithValue("@Department",      vm.Department);
                cmd.Parameters.AddWithValue("@Section",         (object?)vm.Section      ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Position",        (object?)vm.Position     ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Reason",          (object?)vm.Reason       ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReqComputer",     vm.ReqComputer);
                cmd.Parameters.AddWithValue("@ComputerType",    (object?)vm.ComputerType ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ComputerNote",    (object?)vm.ComputerNote ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReqEmail",        vm.ReqEmail);
                cmd.Parameters.AddWithValue("@EmailRequest",    (object?)vm.EmailRequest ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@NetworkDrives",   JsonSerializer.Serialize(vm.NetworkDrives));
                cmd.Parameters.AddWithValue("@Programs",        JsonSerializer.Serialize(vm.SelectedPrograms));
                cmd.Parameters.AddWithValue("@ProgramOther",    (object?)vm.ProgramOther ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ReqVPN",          vm.ReqVPN);
                cmd.Parameters.AddWithValue("@VPNType",         (object?)vm.VPNType      ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@VPNFrom",         vm.VPNFrom.HasValue ? vm.VPNFrom.Value : DBNull.Value);
                cmd.Parameters.AddWithValue("@VPNTo",           vm.VPNTo.HasValue   ? vm.VPNTo.Value   : DBNull.Value);
                cmd.Parameters.AddWithValue("@ApprDeptManager", (object?)vm.ApprDeptManager ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ApprManagingDir", (object?)vm.ApprManagingDir ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ApprITManager",   (object?)vm.ApprITManager   ?? DBNull.Value);

                var outId = new SqlParameter("@NewTicketId", SqlDbType.UniqueIdentifier)
                            { Direction = ParameterDirection.Output };
                cmd.Parameters.Add(outId);
                cmd.ExecuteNonQuery();

                var newId = (Guid)outId.Value;
                _ = NotifyDeptManagerAsync(newId, vm);

                TempData["SuccessMsg"] = "Ticket submitted successfully — awaiting Department Manager approval";
                return RedirectToAction("Detail", new { id = newId });
            }
            catch (Exception ex)
            {
                ModelState.AddModelError("", $"Error: {ex.Message}");
                return View(vm);
            }
        }

        public IActionResult Detail(Guid id)
        {
            var session = GetSession();
            if (session == null) return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
            ViewBag.TicketId = id;
            return View();
        }

        public IActionResult MyTickets()
        {
            var session = GetSession();
            if (session == null) return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
            return View();
        }

        public IActionResult Pending()
        {
            var session = GetSession();
            if (session == null) return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
            if (!session.IsAnyApprover) return RedirectToAction("MyTickets");
            return View();
        }

        // ════════════════════════════════════════════════════════════
        //  JSON ENDPOINTS
        // ════════════════════════════════════════════════════════════

        // GET /Ticket/GetMyManager
        public IActionResult GetMyManager()
        {
            var session = GetSession();
            if (session == null) return Unauthorized();
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetMGRByMySamAcc", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SamAcc", session.SamAcc);

                var samMgr   = new SqlParameter("@SamAccMgr",   SqlDbType.NVarChar, 100) { Direction = ParameterDirection.Output };
                var emailMgr = new SqlParameter("@SamAccEmail", SqlDbType.NVarChar, 512) { Direction = ParameterDirection.Output };
                cmd.Parameters.Add(samMgr);
                cmd.Parameters.Add(emailMgr);
                cmd.ExecuteNonQuery();

                var mgrSam   = samMgr.Value   == DBNull.Value ? "" : samMgr.Value.ToString()!;
                var mgrEmail = emailMgr.Value == DBNull.Value ? "" : emailMgr.Value.ToString()!;

                if (string.IsNullOrEmpty(mgrSam))
                    return Json(new { found = false });

                string displayName = mgrSam;
                using var cmd2 = new SqlCommand(
                    "SELECT DISPNAME FROM [BT_HR].[dbo].[onl_TBADUsers] WHERE SAMACC=@s AND empstatus=1", conn);
                cmd2.Parameters.AddWithValue("@s", mgrSam);
                var n = cmd2.ExecuteScalar();
                if (n != null) displayName = n.ToString()!;

                return Json(new { found = true, samAcc = mgrSam, displayName, email = mgrEmail });
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // GET /Ticket/GetApprovers?funCode=7
        // ใช้ sp_GetApprovers — Cross-DB: BTITReq.TBUserFunction + BT_HR
        public IActionResult GetApprovers(int funCode)
        {
            var session = GetSession();
            if (session == null) return Unauthorized();
            try
            {
                var list    = new List<object>();
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetApprovers", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@FunCode", funCode);

                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    list.Add(new {
                        samAcc      = reader["SamAcc"].ToString(),
                        displayName = reader["DisplayName"].ToString(),
                        email       = reader["Email"]?.ToString() ?? "",
                        department  = reader["Department"]?.ToString() ?? ""
                    });

                return Json(list);
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // GET /Ticket/GetITAdmins — ดึงรายชื่อ IT Admin (FUNCODE=5) สำหรับแสดงใน Create form
        public IActionResult GetITAdmins()
        {
            var session = GetSession();
            if (session == null) return Unauthorized();
            try
            {
                var list    = new List<object>();
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetITAdmins", conn);
                cmd.CommandType = CommandType.StoredProcedure;

                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    list.Add(new {
                        samAcc      = reader["SamAcc"].ToString(),
                        displayName = reader["DisplayName"].ToString(),
                        email       = reader["Email"]?.ToString() ?? "",
                        department  = reader["Department"]?.ToString() ?? ""
                    });

                return Json(list);
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // GET /Ticket/GetMyTickets
        public IActionResult GetMyTickets()
        {
            var session = GetSession();
            if (session == null) return Unauthorized();
            return GetTicketList(samAcc: session.SamAcc);
        }

        // GET /Ticket/GetPending
        public IActionResult GetPending()
        {
            var session = GetSession();
            if (session == null) return Unauthorized();

            int funCode = 0;
            if      (session.IsAdmin)            funCode = 9;
            else if (session.IsDeptManager)      funCode = 8;
            else if (session.IsManagingDirector) funCode = 4;
            else if (session.IsITManager)        funCode = 7;
            else if (session.IsITAdmin)          funCode = 5;
            else if (session.IsITPIC)            funCode = 6;

            if (funCode == 0) return Json(new List<object>());
            return GetTicketList(funCode: funCode, approverSamAcc: funCode == 9 ? null : session.SamAcc);
        }

        // GET /Ticket/GetPendingCount
        public IActionResult GetPendingCount()
        {
            var session = GetSession();
            if (session == null) return Json(new { count = 0 });

            int funCode = 0;
            if      (session.IsAdmin)            funCode = 9;
            else if (session.IsDeptManager)      funCode = 8;
            else if (session.IsManagingDirector) funCode = 4;
            else if (session.IsITManager)        funCode = 7;
            else if (session.IsITAdmin)          funCode = 5;
            else if (session.IsITPIC)            funCode = 6;

            if (funCode == 0) return Json(new { count = 0 });

            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetTicketList", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SamAcc",          DBNull.Value);
                cmd.Parameters.AddWithValue("@Status",          DBNull.Value);
                cmd.Parameters.AddWithValue("@FunCode",         funCode);
                cmd.Parameters.AddWithValue("@ApproverSamAcc",  funCode == 9 ? (object)DBNull.Value : session.SamAcc);
                cmd.Parameters.AddWithValue("@PageNo",   1);
                cmd.Parameters.AddWithValue("@PageSize", 1);

                using var reader = cmd.ExecuteReader();
                int count = reader.Read() && reader["TotalCount"] != DBNull.Value
                            ? Convert.ToInt32(reader["TotalCount"]) : 0;

                return Json(new { count });
            }
            catch { return Json(new { count = 0 }); }
        }

        // GET /Ticket/GetDetail/{id}
        public IActionResult GetDetail(Guid id)
        {
            var session = GetSession();
            if (session == null) return Unauthorized();
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetTicketById", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@TicketId", id);

                object? ticket = null;
                var drives   = new List<object>();
                var programs = new List<object>();
                var logs     = new List<object>();

                using var reader = cmd.ExecuteReader();
                if (reader.Read())
                    ticket = new {
                        ticketId       = reader["TicketId"].ToString(),
                        docNumber      = reader["DocNumber"].ToString(),
                        samAcc         = reader["SamAcc"].ToString(),
                        requesterName  = reader["RequesterName"].ToString(),
                        requesterEmail = reader["RequesterEmail"].ToString(),
                        department     = reader["Department"].ToString(),
                        reason         = reader["Reason"] == DBNull.Value ? null : reader["Reason"].ToString(),
                        reqComputer    = (bool)reader["ReqComputer"],
                        reqEmail       = (bool)reader["ReqEmail"],
                        reqNetwork     = (bool)reader["ReqNetwork"],
                        reqPrograms    = (bool)reader["ReqPrograms"],
                        reqVPN         = (bool)reader["ReqVPN"],
                        vpnType        = reader["VPNType"] == DBNull.Value ? null : reader["VPNType"].ToString(),
                        status         = reader["Status"].ToString(),
                        apprITPIC      = reader["ApprITPIC"] == DBNull.Value ? null : reader["ApprITPIC"].ToString(),
                        itpicName      = reader["ITPICName"] == DBNull.Value ? null : reader["ITPICName"].ToString(),
                        createdAt      = reader["CreatedAt"],
                        completedAt    = reader["CompletedAt"] == DBNull.Value ? null : reader["CompletedAt"].ToString()
                    };

                reader.NextResult();
                while (reader.Read())
                    drives.Add(new {
                        drive = reader["Drive"].ToString(),
                        driveRead = (bool)reader["DriveRead"],
                        driveWrite = (bool)reader["DriveWrite"],
                        customPath = reader["CustomPath"] == DBNull.Value ? null : reader["CustomPath"].ToString()
                    });

                reader.NextResult();
                while (reader.Read())
                    programs.Add(new { programName = reader["ProgramName"].ToString() });

                reader.NextResult();
                while (reader.Read())
                    logs.Add(new {
                        logId        = reader["LogId"].ToString(),
                        funCode      = (int)reader["ApproverFunCode"],
                        approverSam  = reader["ApproverSam"].ToString(),
                        approverName = reader["ApproverDisplayName"] == DBNull.Value ? null : reader["ApproverDisplayName"].ToString(),
                        action       = reader["Action"].ToString(),
                        assignedTo   = reader["AssignedTo"] == DBNull.Value ? null : reader["AssignedTo"].ToString(),
                        remark       = reader["Remark"] == DBNull.Value ? null : reader["Remark"].ToString(),
                        actionAt     = reader["ActionAt"]
                    });

                return Json(new { ticket, drives, programs, logs });
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // POST /Ticket/Approve
        [HttpPost]
        public IActionResult Approve([FromBody] ApproveRequest body)
        {
            var session = GetSession();
            if (session == null) return Json(new { ok = false, msg = "Please sign in again" });
            if (!session.IsAnyApprover) return Json(new { ok = false, msg = "You do not have approval permission" });

            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                // ดึงข้อมูลก่อน approve
                string docNumber = "", requesterName = "", requesterEmail = "", newStatus = "";
                bool   reqVPN    = false;
                string? apprITMgr = null;

                using var cmdGet = new SqlCommand(
                    "SELECT DocNumber, RequesterName, RequesterEmail, ReqVPN, ApprITManager FROM dbo.TBITTicket WHERE TicketId=@id", conn);
                cmdGet.Parameters.AddWithValue("@id", body.RequestId);
                using (var r = cmdGet.ExecuteReader())
                    if (r.Read())
                    {
                        docNumber      = r["DocNumber"].ToString()!;
                        requesterName  = r["RequesterName"].ToString()!;
                        requesterEmail = r["RequesterEmail"].ToString()!;
                        reqVPN         = (bool)r["ReqVPN"];
                        apprITMgr      = r["ApprITManager"] == DBNull.Value ? null : r["ApprITManager"].ToString();
                    }

                using var cmd = new SqlCommand("sp_ApproveTicket", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@TicketId",    body.RequestId);
                cmd.Parameters.AddWithValue("@ApproverSam", session.SamAcc);
                cmd.Parameters.AddWithValue("@ApproverName",session.FullName);
                cmd.Parameters.AddWithValue("@Action",      body.Action);
                cmd.Parameters.AddWithValue("@Remark",      (object?)body.Remark   ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@AssignTo",    (object?)body.AssignTo ?? DBNull.Value);

                using var result = cmd.ExecuteReader();
                if (result.Read()) newStatus = result["NewStatus"]?.ToString() ?? "";

                _ = NotifyWorkflowAsync(body.RequestId, docNumber, requesterName, requesterEmail,
                                        newStatus, body.Action, session, apprITMgr, body.AssignTo);

                return Json(new { ok = true, msg = $"{body.Action} completed successfully", newStatus });
            }
            catch (Exception ex) { return Json(new { ok = false, msg = ex.Message }); }
        }

        // ── Helper ────────────────────────────────────────────────────
        private IActionResult GetTicketList(string? samAcc = null, int? funCode = null, string? approverSamAcc = null)
        {
            try
            {
                var rows    = new List<object>();
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetTicketList", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@SamAcc",         (object?)samAcc         ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Status",         DBNull.Value);
                cmd.Parameters.AddWithValue("@FunCode",        (object?)funCode        ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@ApproverSamAcc", (object?)approverSamAcc ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@PageNo",   1);
                cmd.Parameters.AddWithValue("@PageSize", 500);

                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add(new {
                        ticketId      = reader["TicketId"].ToString(),
                        docNumber     = reader["DocNumber"].ToString(),
                        requesterName = reader["RequesterName"].ToString(),
                        department    = reader["Department"].ToString(),
                        status        = reader["Status"].ToString(),
                        statusLabel   = reader["StatusLabel"].ToString(),
                        reqComputer   = (bool)reader["ReqComputer"],
                        reqEmail      = (bool)reader["ReqEmail"],
                        reqNetwork    = (bool)reader["ReqNetwork"],
                        reqPrograms   = (bool)reader["ReqPrograms"],
                        reqVPN        = (bool)reader["ReqVPN"],
                        apprITPIC     = reader["ApprITPIC"] == DBNull.Value ? null : reader["ApprITPIC"].ToString(),
                        createdAt     = reader["CreatedAt"]
                    });

                return Json(rows);
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // ── Email Notifications ───────────────────────────────────────
        private async Task NotifyDeptManagerAsync(Guid ticketId, TicketViewModel vm)
        {
            try
            {
                var emails = !string.IsNullOrEmpty(vm.ApprDeptManager)
                    ? GetEmailBySam(vm.ApprDeptManager)
                    : GetEmailsByFunCode(8);
                if (!emails.Any()) return;

                var link = $"{_settings.URLSITE}Ticket/Detail/{ticketId}";
                var body = $@"<p>Dear Department Manager,</p>
                    <p>New IT Ticket Request awaiting your approval.</p>
                    <table style='font-size:14px;border-collapse:collapse'>
                    <tr><td style='color:#607080;padding:4px 12px 4px 0'>Requester:</td><td><b>{vm.RequesterName}</b></td></tr>
                    <tr><td style='color:#607080;padding:4px 12px 4px 0'>Department:</td><td>{vm.Department}</td></tr>
                    </table>
                    <p style='margin-top:16px'>
                    <a href='{link}' style='background:#231f20;color:#fff;padding:10px 24px;border-radius:6px;text-decoration:none;font-weight:bold'>
                    Click here to approve</a></p>";

                await SendMailAsync(string.Join(";", emails),
                    $"[ITTicket] New Request from {vm.RequesterName} — Pending Approval", body);
            }
            catch { }
        }

        private async Task NotifyWorkflowAsync(Guid ticketId, string docNumber,
            string requesterName, string requesterEmail, string newStatus,
            string action, UserSessionModel approver, string? selITMgr, string? assignedPIC)
        {
            try
            {
                var link = $"{_settings.URLSITE}Ticket/Detail/{ticketId}";

                if (action == "Reject")
                {
                    await SendMailAsync(requesterEmail,
                        $"[ITTicket] {docNumber} — Rejected",
                        $"<p>Dear {requesterName},</p><p>Your ticket <b>{docNumber}</b> has been <b style='color:#c62828'>Rejected</b> by {approver.FullName}.</p><p><a href='{link}'>View details</a></p>");
                    return;
                }

                var (nextFunCode, nextRole) = newStatus switch
                {
                    "PendingManagingDir"   => (4, "Managing Director"),
                    "PendingITMgr"         => (7, "IT Manager"),
                    "PendingITAdminAssign" => (5, "IT Admin (Assign PIC)"),
                    "PendingITPIC"         => (6, "IT Person Incharge"),
                    "PendingITAdminClose"  => (9, "IT Admin (Close Ticket)"),
                    "Completed"            => (0, ""),
                    _                      => (0, "")
                };

                if (nextFunCode > 0)
                {
                    // IT PIC ใช้ assignedPIC ที่เพิ่งเลือก
                    var emails = nextFunCode == 6 && !string.IsNullOrEmpty(assignedPIC)
                        ? GetEmailBySam(assignedPIC)
                        : nextFunCode == 7 && !string.IsNullOrEmpty(selITMgr)
                            ? GetEmailBySam(selITMgr)
                            : GetEmailsByFunCode(nextFunCode);

                    if (emails.Any())
                        await SendMailAsync(string.Join(";", emails),
                            $"[ITTicket] {docNumber} — Pending {nextRole}",
                            $@"<p>Dear {nextRole},</p>
                            <p>Ticket <b>{docNumber}</b> from {requesterName} is awaiting your action.</p>
                            <p><a href='{link}' style='background:#231f20;color:#fff;padding:10px 24px;border-radius:6px;text-decoration:none;font-weight:bold'>
                            Click here to proceed</a></p>");
                }
                else if (newStatus == "Completed")
                {
                    await SendMailAsync(requesterEmail,
                        $"[ITTicket] {docNumber} — Completed",
                        $"<p>Dear {requesterName},</p><p>Your ticket <b>{docNumber}</b> has been <b style='color:#2e7d32'>Completed</b>.</p><p><a href='{link}'>View details</a></p>");
                }
            }
            catch { }
        }

        private List<string> GetEmailBySam(string samAcc)
        {
            var emails = new List<string>();
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();
                using var cmd = new SqlCommand(
                    "SELECT UEMAIL FROM [BT_HR].[dbo].[onl_TBADUsers] WHERE SAMACC=@s AND empstatus=1 AND UEMAIL IS NOT NULL AND UEMAIL<>''", conn);
                cmd.Parameters.AddWithValue("@s", samAcc);
                var r = cmd.ExecuteScalar();
                if (r != null) emails.Add(r.ToString()!);
            }
            catch { }
            return emails;
        }

        private List<string> GetEmailsByFunCode(int funCode)
        {
            var emails = new List<string>();
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();
                const string sql = @"
                    SELECT e.UEMAIL FROM dbo.TBUserFunction f
                    JOIN   [BT_HR].[dbo].[onl_TBADUsers] e
                           ON e.SAMACC = f.USERLOGON COLLATE THAI_CI_AS
                    WHERE  f.FUNCODE=@fc AND f.FLAG=1 AND e.empstatus=1
                      AND  e.UEMAIL IS NOT NULL AND e.UEMAIL<>''";
                using var cmd = new SqlCommand(sql, conn);
                cmd.Parameters.AddWithValue("@fc", funCode);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                {
                    var e = reader["UEMAIL"]?.ToString();
                    if (!string.IsNullOrEmpty(e)) emails.Add(e);
                }
            }
            catch { }
            return emails;
        }

        private async Task SendMailAsync(string addresses, string subject, string body)
        {
            if (string.IsNullOrEmpty(addresses)) return;
            try
            {
                var payload = new {
                    Addresses = addresses,
                    Form      = _settings.MailForm,
                    Subject   = subject,
                    Body      = body,
                    Priority  = 1
                };
                await _http.CreateClient().PostAsJsonAsync(LocalMailUrl, payload);
            }
            catch { }
        }
    }
}
