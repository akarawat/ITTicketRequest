using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Mvc;
using System.Data;
using ExcelDataReader;

namespace ITTicketRequest.Controllers
{
    public class Moni4Controller : Controller
    {
        private readonly ILogger<Moni4Controller> _logger;
        private readonly IConfiguration _configuration;
        public string REQ_ID;
        public Moni4Controller(ILogger<Moni4Controller> logger, IConfiguration configuration)
        {
            _logger = logger;
            _configuration = configuration;
        }
        public IActionResult Index(string user)
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error() {
            return View();
        }
        public IActionResult Excelimport()
        {
            return View();
        }

        [HttpPost("ImportResult")]
        public async Task<IActionResult> ImportResult(IFormFile file)
        {
            string[] strMsg = new string[3];
            IConfiguration _configuration = new ConfigurationBuilder()
                                .SetBasePath(Directory.GetCurrentDirectory())
                                .AddJsonFile("appsettings.json")
                                .Build();
            string ExcelRootPath = _configuration[key: "TBCorApiServices:ExcelRootPath"];
            try
            {
                string _FileName = Path.GetFileName(file.FileName);
                string _path = Path.Combine(ExcelRootPath, DateTime.Now.ToString("ddMMyyHHmm") + _FileName);
                if (file.Length > 0)
                {
                    using FileStream fs = new(_path, FileMode.Create);
                    await file.OpenReadStream().CopyToAsync(fs, 1073741824);
                    file.OpenReadStream().Close();
                    file.OpenReadStream().Flush();
                }
                Insert_Serial(_path);
                ViewBag.Message = "Success";
            }
            catch
            {
                ViewBag.Message = "Error";
            }
            return View("Excelimport");
        }
        public async void Insert_Serial(string fExcelPath)
        {
            if (fExcelPath == "") return;
            //Start to read <---
            List<string> sheetNames = new List<string>();
            DataTableCollection tables = ReadFromExcel(fExcelPath, ref sheetNames);
            int rows = 0;
            if (tables != null)
            {
                foreach (DataTable dt in tables)
                {
                    rows = dt.Rows.Count;
                    if (rows != 0)
                    {
                        DataTable dtImp = new DataTable();
                        dtImp.Columns.Add("SERIAL_NO");
                        dtImp.Columns.Add("WORK_ORDER");
                        dtImp.Columns.Add("flag_new_model");
                        dtImp.Columns.Add("itemno");
                        dtImp.Columns.Add("dimens1");
                        dtImp.Columns.Add("dimens2");
                        dtImp.Columns.Add("prodname");

                        foreach (DataRow row in dt.Rows)
                        {
                            if (row[0] != null)
                            {
                                if (row[0].ToString() != "Item number")
                                {
                                    DataRow dtrow = dtImp.NewRow();
                                    dtrow["itemno"] = row[0].ToString() == null ? "" : row[0].ToString();
                                    dtrow["dimens1"] = row[1].ToString() == null ? "" : row[1].ToString();
                                    dtrow["dimens2"] = row[2].ToString() == null ? "" : row[2].ToString();
                                    dtrow["WORK_ORDER"] = row[3].ToString() == null ? "" : row[3].ToString().Replace("WO-","");
                                    string[] arrpd = row[4].ToString().Split('/');
                                    dtrow["prodname"] = arrpd.Length == 1 ? arrpd[0].ToString() : arrpd[1].ToString();

                                    
                                    dtrow["SERIAL_NO"] = row[9].ToString();

                                    string[] arrsn = row[9].ToString().Split('/');
                                    dtrow["flag_new_model"] = (arrsn.Length - 1).ToString();

                                    dtImp.Rows.Add(dtrow);
                                }
                            }
                        }
                        //--Insert into Data Collection
                        try
                        {
                            string SqlconString = _configuration[key: "ConnectionStrings:moni4ConnDB"];
                            SqlConnection sqlCon = null;
                            using (sqlCon = new SqlConnection(SqlconString))
                            {
                                sqlCon.Open();

                                SqlCommand sql_cmnd = new SqlCommand("SP_MigSerialData", sqlCon);
                                sql_cmnd.CommandType = CommandType.StoredProcedure;

                                var sqlParam = new SqlParameter();
                                sqlParam.ParameterName = "@TempTable";
                                sqlParam.SqlDbType = SqlDbType.Structured;
                                sqlParam.Value = dtImp; // dt;
                                sql_cmnd.Parameters.Add(sqlParam);

                                sql_cmnd.Parameters.Add("@IROW", SqlDbType.Int);
                                sql_cmnd.Parameters["@IROW"].Direction = ParameterDirection.Output;
                                sql_cmnd.Parameters.Add("@UROW", SqlDbType.Int);
                                sql_cmnd.Parameters["@UROW"].Direction = ParameterDirection.Output;

                                sql_cmnd.ExecuteNonQuery();

                                string iRow = "0";
                                iRow = sql_cmnd.Parameters["@IROW"].Value == null ? "0" : sql_cmnd.Parameters["@IROW"].Value.ToString();
                                string uRow = "0";
                                uRow = sql_cmnd.Parameters["@UROW"].Value == null ? "0" : sql_cmnd.Parameters["@UROW"].Value.ToString();
                                sqlCon.Close();
                            }
                        }
                        catch (Exception ex)
                        {

                        }
                        
                    }
                }
            }
        }

        [HttpPost("ImportResultWo")]
        public async Task<IActionResult> ImportResultWo(IFormFile file)
        {
            string[] strMsg = new string[3];
            IConfiguration _configuration = new ConfigurationBuilder()
                                .SetBasePath(Directory.GetCurrentDirectory())
                                .AddJsonFile("appsettings.json")
                                .Build();

            string ExcelRootPath = _configuration[key: "TBCorApiServices:ExcelRootPath"];
            try
            {
                string _FileName = Path.GetFileName(file.FileName);
                //string _path = Path.Combine("~/UploadedFiles", _FileName);
                string _path = Path.Combine(ExcelRootPath, DateTime.Now.ToString("ddMMyyHHmm") + _FileName);
                if (file.Length > 0)
                {
                    //<---- Start to Copy 1073741824
                    using FileStream fs = new(_path, FileMode.Create);
                    await file.OpenReadStream().CopyToAsync(fs, 1073741824);
                    file.OpenReadStream().Close();
                    file.OpenReadStream().Flush();
                }
                Insert_SerialWo(_path);
                ViewBag.Message = "Success";
            }
            catch
            {
                ViewBag.Message = "Error";
            }
            return View("Excelimport");
        }
        public async void Insert_SerialWo(string fExcelPath)
        {
            if (fExcelPath == "") return;
            //Start to read <---
            List<string> sheetNames = new List<string>();
            DataTableCollection tables = ReadFromExcel(fExcelPath, ref sheetNames);
            int rows = 0;
            if (tables != null)
            {
                foreach (DataTable dt in tables)
                {
                    rows = dt.Rows.Count;
                    if (rows != 0)
                    {
                        DataTable dtImp = new DataTable();
                        dtImp.Columns.Add("WORK_ORDER");
                        dtImp.Columns.Add("WO_QTY");

                        foreach (DataRow row in dt.Rows)
                        {
                            if (row[0] != null)
                            {
                                if (row[0].ToString() != "Production")
                                {
                                    DataRow dtrow = dtImp.NewRow();
                                    
                                    dtrow["WORK_ORDER"] = row[0].ToString() == null ? "" : row[0].ToString().Replace("WO-","");

                                    dtrow["WO_QTY"] = row[5].ToString() == null ? "0" : row[5].ToString();

                                    dtImp.Rows.Add(dtrow);
                                }
                            }
                        }
                        //--Insert into Data Collection
                        try
                        {
                            string SqlconString = _configuration[key: "ConnectionStrings:moni4ConnDB"];
                            SqlConnection sqlCon = null;
                            using (sqlCon = new SqlConnection(SqlconString))
                            {
                                sqlCon.Open();

                                SqlCommand sql_cmnd = new SqlCommand("SP_MigWOData", sqlCon);
                                sql_cmnd.CommandType = CommandType.StoredProcedure;

                                var sqlParam = new SqlParameter();
                                sqlParam.ParameterName = "@TempTable";
                                sqlParam.SqlDbType = SqlDbType.Structured;
                                sqlParam.Value = dtImp; // dt;
                                sql_cmnd.Parameters.Add(sqlParam);

                                sql_cmnd.Parameters.Add("@IROW", SqlDbType.Int);
                                sql_cmnd.Parameters["@IROW"].Direction = ParameterDirection.Output;
                                sql_cmnd.ExecuteNonQuery();
                                string iRow = "0";
                                iRow = sql_cmnd.Parameters["@IROW"].Value == null ? "0" : sql_cmnd.Parameters["@IROW"].Value.ToString();
                                sqlCon.Close();
                            }
                        }
                        catch (Exception ex)
                        {

                        }
                        
                    }

                }
            }
            else
            {
            }
        }
        
        DataTableCollection ReadFromExcel(string filePath, ref List<string> sheetNames)
        {
            try
            {
                DataTableCollection tableCollection = null;

                using (var stream = System.IO.File.Open(filePath, FileMode.Open, FileAccess.Read))
                {
                    System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);

                    using (IExcelDataReader reader = ExcelReaderFactory.CreateReader(stream))
                    {
                        DataSet result = reader.AsDataSet(new ExcelDataSetConfiguration()
                        {
                            ConfigureDataTable = (_) => new ExcelDataTableConfiguration() { UseHeaderRow = true }
                        });

                        tableCollection = result.Tables;

                        foreach (DataTable table in tableCollection)
                        {
                            sheetNames.Add(table.TableName);
                        }
                    }
                }

                return tableCollection;
            }
            catch (Exception)
            {
                return null;
            }
        }

    }
}
