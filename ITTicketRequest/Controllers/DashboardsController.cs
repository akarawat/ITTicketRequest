using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Microsoft.Data.SqlClient;
using ITTicketRequest.Models;
using System.Text.Json;

namespace ITTicketRequest.Controllers
{
    public class DashboardsController : Controller
    {
        private readonly IConfiguration _config;
        private readonly AppSettingsModel _settings;

        public DashboardsController(IConfiguration config,
                                    IOptions<AppSettingsModel> settings)
        {
            _config = config;
            _settings = settings.Value;
        }

        // ── GET /Dashboards/Index ──────────────────────────────────────
        public IActionResult Index(string? id, string? user,
                                   string? email, string? fname,
                                   string? depart)
        {
            var existing = HttpContext.Session.GetString("UserSession");
            var authenUrl = _config["TBCorApiServices:AuthenUrl"] ?? "/";

            if (string.IsNullOrEmpty(id) && string.IsNullOrEmpty(existing))
                return Redirect(authenUrl);

            if (!string.IsNullOrEmpty(id))
            {
                var samAcc = UserSessionModel.ParseSamAcc(user ?? "");
                var session = new UserSessionModel
                {
                    Id = id,
                    UserLogon = user ?? "",
                    SamAcc = samAcc,
                    Email = email ?? "",
                    FullName = fname ?? "",
                    Department = depart ?? "",
                    IsUser = true
                };
                LoadUserRoles(session, samAcc);
                HttpContext.Session.SetString("UserSession",
                    JsonSerializer.Serialize(session));
            }
            return View();
        }

        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            return Redirect(_config["TBCorApiServices:AuthenUrl"] ?? "/");
        }

        // ── LoadUserRoles ──────────────────────────────────────────────
        // FUNCODE mapping:
        //   4 = Managing Director
        //   5 = IT Admin / Staff
        //   6 = IT Person Incharge (IT PIC)
        //   7 = IT Manager
        //   8 = Department Manager
        //   9 = System Admin
        private void LoadUserRoles(UserSessionModel session, string samAcc)
        {
            try
            {
                var connStr = _config.GetConnectionString("BTITTicketConn");
                using var conn = new SqlConnection(connStr);
                conn.Open();

                // Cross-DB: TBUserFunction อยู่ใน BTITReq
                const string sql = @"
                    SELECT FUNCODE FROM [BTITReq].[dbo].[TBUserFunction]
                    WHERE  USERLOGON = @sam AND FLAG = 1";

                using var cmd = new SqlCommand(sql, conn);
                cmd.Parameters.AddWithValue("@sam", samAcc);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                {
                    switch (reader.GetInt32(0))
                    {
                        case 9: session.IsAdmin = true; break;
                        case 8: session.IsDeptManager = true; break;
                        case 7: session.IsITManager = true; break;
                        case 6: session.IsITPIC = true; break;
                        case 5: session.IsITAdmin = true; break;
                        case 4: session.IsManagingDirector = true; break;
                    }
                }
            }
            catch { session.IsUser = true; }
        }
    }
}
