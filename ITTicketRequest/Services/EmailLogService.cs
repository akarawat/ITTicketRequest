using System.Text;

namespace ITTicketRequest.Services
{
    /// <summary>
    /// บันทึก Log การส่งอีเมล์ลงไฟล์ Text แยกตามวัน
    /// ตัวอย่าง: logs/email/email_2026-05-27.log
    /// </summary>
    public class EmailLogService
    {
        private readonly string _logFolder;

        public EmailLogService(IWebHostEnvironment env)
        {
            _logFolder = Path.Combine(env.ContentRootPath, "logs", "email");
            Directory.CreateDirectory(_logFolder);
        }

        /// <summary>
        /// เขียน Log การส่งเมล์
        /// </summary>
        /// <param name="toAddresses">อีเมล์ผู้รับ (คั่นด้วย ;)</param>
        /// <param name="subject">หัวข้ออีเมล์</param>
        /// <param name="docNumber">เลข Ticket เช่น IT-2026-0001</param>
        /// <param name="success">ส่งสำเร็จหรือไม่</param>
        /// <param name="trigger">ชื่อ Action ที่ trigger การส่ง เช่น NotifyDeptMgr, NotifyITMgr</param>
        /// <param name="errorMsg">ข้อความ Error ถ้าส่งไม่สำเร็จ</param>
        public void Write(string toAddresses, string subject, string docNumber,
                          bool success, string trigger = "", string? errorMsg = null)
        {
            try
            {
                string fileName = $"email_{DateTime.Now:yyyy-MM-dd}.log";
                string filePath = Path.Combine(_logFolder, fileName);

                var sb = new StringBuilder();
                sb.AppendLine("──────────────────────────────────────────────────");
                sb.AppendLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]  {(success ? "✓ SENT" : "✗ FAILED")}");
                sb.AppendLine($"  Trigger  : {trigger}");
                sb.AppendLine($"  DocNo    : {docNumber}");
                sb.AppendLine($"  To       : {toAddresses}");
                sb.AppendLine($"  Subject  : {subject}");
                if (!success && !string.IsNullOrEmpty(errorMsg))
                    sb.AppendLine($"  Error    : {errorMsg}");

                File.AppendAllText(filePath, sb.ToString(), Encoding.UTF8);
            }
            catch
            {
                // ไม่ให้ Log Error มา block การทำงานหลัก
            }
        }

        /// <summary>
        /// เขียน Log กรณีไม่มีอีเมล์ผู้รับ (หาไม่เจอ)
        /// </summary>
        public void WriteNoRecipient(string docNumber, string trigger, int? funCode = null)
        {
            try
            {
                string fileName = $"email_{DateTime.Now:yyyy-MM-dd}.log";
                string filePath = Path.Combine(_logFolder, fileName);

                var sb = new StringBuilder();
                sb.AppendLine("──────────────────────────────────────────────────");
                sb.AppendLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]  ⚠ SKIPPED (no recipient)");
                sb.AppendLine($"  Trigger  : {trigger}");
                sb.AppendLine($"  DocNo    : {docNumber}");
                if (funCode.HasValue)
                    sb.AppendLine($"  FunCode  : {funCode} (ไม่พบอีเมล์ในระบบ)");

                File.AppendAllText(filePath, sb.ToString(), Encoding.UTF8);
            }
            catch { }
        }
    }
}
