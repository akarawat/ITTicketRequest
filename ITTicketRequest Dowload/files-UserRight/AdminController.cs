using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using ITTicketRequest.Models;
using System.Text.Json;
using System.Data;

namespace ITTicketRequest.Controllers
{
    public class AdminController : Controller
    {
        private readonly IConfiguration _config;

        public AdminController(IConfiguration config) => _config = config;

        private UserSessionModel? GetSession()
        {
            var json = HttpContext.Session.GetString("UserSession");
            if (string.IsNullOrEmpty(json)) return null;
            return JsonSerializer.Deserialize<UserSessionModel>(json);
        }

        private string AuthenUrl => _config["TBCorApiServices:AuthenUrl"] ?? "/";
        private bool IsAdminUser(UserSessionModel? s) => s != null && s.IsAdmin;

        // ── GET /Admin/UserRights ─────────────────────────────────────
        public IActionResult UserRights()
        {
            var session = GetSession();
            if (session == null)          return Redirect(AuthenUrl);
            if (!IsAdminUser(session))    return RedirectToAction("Index", "Dashboards");
            return View();
        }

        // ── GET /Admin/GetUsers ───────────────────────────────────────
        public IActionResult GetUsers(string? search, string? dept)
        {
            var session = GetSession();
            if (session == null)       return Unauthorized();
            if (!IsAdminUser(session)) return Forbid();
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetUserFunctions", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@Search",     (object?)search ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Department", (object?)dept   ?? DBNull.Value);

                var users = new List<object>();
                var depts = new List<string>();

                using var reader = cmd.ExecuteReader();

                // Result 1: Users + roles
                while (reader.Read())
                    users.Add(new {
                        samAcc              = reader["SamAcc"].ToString(),
                        displayName         = reader["DisplayName"].ToString(),
                        displayNameTH       = reader["DisplayNameTH"]?.ToString(),
                        email               = reader["Email"]?.ToString(),
                        department          = reader["Department"]?.ToString(),
                        position            = reader["Position"]?.ToString(),
                        hasRequester        = (int)reader["HasRequester"]        == 1,
                        hasDeptManager      = (int)reader["HasDeptManager"]      == 1,
                        hasCrossDept        = (int)reader["HasCrossDept"]        == 1,
                        hasITManager        = (int)reader["HasITManager"]        == 1,
                        hasNetworkAdmin     = (int)reader["HasNetworkAdmin"]     == 1,
                        hasManagingDirector = (int)reader["HasManagingDirector"] == 1,
                        hasSysAdmin         = (int)reader["HasSysAdmin"]         == 1
                    });

                // Result 2: Departments
                reader.NextResult();
                while (reader.Read())
                    depts.Add(reader["DEPART"].ToString() ?? "");

                return Json(new { users, depts });
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }

        // ── POST /Admin/SetFunction ───────────────────────────────────
        [HttpPost]
        public IActionResult SetFunction([FromBody] SetFunctionRequest body)
        {
            var session = GetSession();
            if (session == null)       return Json(new { ok = false, msg = "Please sign in again" });
            if (!IsAdminUser(session)) return Json(new { ok = false, msg = "You do not have permission to manage User Rights" });
            if (body.FunCode == 1)     return Json(new { ok = false, msg = "FUNCODE=1 (Requester) is automatic — no manual assignment needed" });

            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_SetUserFunction", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@UserLogon", body.UserLogon);
                cmd.Parameters.AddWithValue("@FunCode",   body.FunCode);
                cmd.Parameters.AddWithValue("@Action",    body.Action);
                cmd.Parameters.AddWithValue("@UpdatedBy", session.SamAcc);
                cmd.ExecuteNonQuery();

                return Json(new { ok = true, msg = $"{body.Action} completed successfully" });
            }
            catch (Exception ex) { return Json(new { ok = false, msg = ex.Message }); }
        }

        // ── GET /Admin/GetLog ─────────────────────────────────────────
        public IActionResult GetLog(string? userLogon)
        {
            var session = GetSession();
            if (session == null)       return Unauthorized();
            if (!IsAdminUser(session)) return Forbid();
            try
            {
                var rows    = new List<object>();
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                using var cmd = new SqlCommand("sp_GetUserFunctionLog", conn);
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.AddWithValue("@UserLogon", (object?)userLogon ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Top", 200);

                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add(new {
                        userLogon = reader["UserLogon"].ToString(),
                        funCode   = (int)reader["FunCode"],
                        funName   = reader["FunName"]?.ToString(),
                        action    = reader["Action"].ToString(),
                        updatedBy = reader["UpdatedBy"].ToString(),
                        updatedAt = reader["UpdatedAt"]
                    });

                return Json(rows);
            }
            catch (Exception ex) { return StatusCode(500, new { error = ex.Message }); }
        }
    }

    // ── DTO ──────────────────────────────────────────────────────────
    public class SetFunctionRequest
    {
        public string UserLogon { get; set; } = "";
        public int    FunCode   { get; set; }
        public string Action    { get; set; } = "";   // Grant | Revoke
    }
}
