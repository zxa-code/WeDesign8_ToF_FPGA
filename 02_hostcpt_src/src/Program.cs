using System;
using System.IO;
using System.Windows.Forms;

namespace SDAM_Rangefinder
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.ThreadException += OnThreadException;
            AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;

            try
            {
                Application.Run(new MainForm());
            }
            catch (Exception ex)
            {
                WriteErrorLog(ex);
                MessageBox.Show("程序异常退出：\r\n" + ex.Message + "\r\n\r\n详细信息见 error.log",
                    "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void OnThreadException(object sender, System.Threading.ThreadExceptionEventArgs e)
        {
            WriteErrorLog(e.Exception);
            MessageBox.Show("界面线程异常：\r\n" + e.Exception.Message + "\r\n\r\n详细信息见 error.log",
                "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        private static void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            Exception ex = e.ExceptionObject as Exception;
            if (ex != null)
            {
                WriteErrorLog(ex);
            }
        }

        private static void WriteErrorLog(Exception ex)
        {
            try
            {
                string path = Path.Combine(Application.StartupPath, "error.log");
                using (StreamWriter writer = new StreamWriter(path, true, System.Text.Encoding.UTF8))
                {
                    writer.WriteLine("==== " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " ====");
                    writer.WriteLine(ex.ToString());
                    writer.WriteLine();
                }
            }
            catch
            {
                // 日志写入失败时不再抛异常。
            }
        }
    }
}
