namespace SDAM_Rangefinder
{
    partial class MainForm
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.GroupBox grpConnection;
        private System.Windows.Forms.Label lblPort;
        private System.Windows.Forms.ComboBox comboBoxPort;
        private System.Windows.Forms.Button btnRefreshPorts;
        private System.Windows.Forms.Label lblBaud;
        private System.Windows.Forms.ComboBox comboBoxBaudRate;
        private System.Windows.Forms.Button btnConnect;
        private System.Windows.Forms.Label lblConnState;
        private System.Windows.Forms.Label lblRateNote;

        private System.Windows.Forms.GroupBox grpLive;
        private System.Windows.Forms.Label lblDistCap;
        private System.Windows.Forms.Label lblDistanceValue;
        private System.Windows.Forms.Label lblIntCap;
        private System.Windows.Forms.Label lblIntensityValue;
        private System.Windows.Forms.Label lblAmbCap;
        private System.Windows.Forms.Label lblAmbientValue;

        private System.Windows.Forms.GroupBox grpDiag;
        private System.Windows.Forms.Label lblDiag;

        private System.Windows.Forms.GroupBox grpChart;
        private System.Windows.Forms.CheckBox chkDistance;
        private System.Windows.Forms.CheckBox chkIntensity;
        private System.Windows.Forms.CheckBox chkAmbient;
        private System.Windows.Forms.Label lblWindow;
        private System.Windows.Forms.ComboBox comboBoxWindow;
        private System.Windows.Forms.Button btnClearChart;
        private System.Windows.Forms.Button btnSaveCsv;
        private System.Windows.Forms.Button btnSavePng;
        private System.Windows.Forms.DataVisualization.Charting.Chart chartDistance;

        private System.Windows.Forms.GroupBox grpStats;
        private System.Windows.Forms.Label lblStats;

        private System.Windows.Forms.GroupBox grpLog;
        private System.Windows.Forms.TextBox txtLog;
        private System.Windows.Forms.Button btnClearLog;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();

            this.grpConnection = new System.Windows.Forms.GroupBox();
            this.lblPort = new System.Windows.Forms.Label();
            this.comboBoxPort = new System.Windows.Forms.ComboBox();
            this.btnRefreshPorts = new System.Windows.Forms.Button();
            this.lblBaud = new System.Windows.Forms.Label();
            this.comboBoxBaudRate = new System.Windows.Forms.ComboBox();
            this.btnConnect = new System.Windows.Forms.Button();
            this.lblConnState = new System.Windows.Forms.Label();
            this.lblRateNote = new System.Windows.Forms.Label();

            this.grpLive = new System.Windows.Forms.GroupBox();
            this.lblDistCap = new System.Windows.Forms.Label();
            this.lblDistanceValue = new System.Windows.Forms.Label();
            this.lblIntCap = new System.Windows.Forms.Label();
            this.lblIntensityValue = new System.Windows.Forms.Label();
            this.lblAmbCap = new System.Windows.Forms.Label();
            this.lblAmbientValue = new System.Windows.Forms.Label();

            this.grpDiag = new System.Windows.Forms.GroupBox();
            this.lblDiag = new System.Windows.Forms.Label();

            this.grpChart = new System.Windows.Forms.GroupBox();
            this.chkDistance = new System.Windows.Forms.CheckBox();
            this.chkIntensity = new System.Windows.Forms.CheckBox();
            this.chkAmbient = new System.Windows.Forms.CheckBox();
            this.lblWindow = new System.Windows.Forms.Label();
            this.comboBoxWindow = new System.Windows.Forms.ComboBox();
            this.btnClearChart = new System.Windows.Forms.Button();
            this.btnSaveCsv = new System.Windows.Forms.Button();
            this.btnSavePng = new System.Windows.Forms.Button();
            this.chartDistance = new System.Windows.Forms.DataVisualization.Charting.Chart();

            this.grpStats = new System.Windows.Forms.GroupBox();
            this.lblStats = new System.Windows.Forms.Label();

            this.grpLog = new System.Windows.Forms.GroupBox();
            this.txtLog = new System.Windows.Forms.TextBox();
            this.btnClearLog = new System.Windows.Forms.Button();

            // ---- 窗体 ----
            this.SuspendLayout();
            this.Text = "ToF激光测距上位机 V2.0（FPGA 文本行）";
            this.ClientSize = new System.Drawing.Size(1340, 660);
            this.MinimumSize = new System.Drawing.Size(1360, 700);
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.None;
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.MainForm_FormClosing);

            // ---- 连接设置 ----
            this.grpConnection.Location = new System.Drawing.Point(20, 10);
            this.grpConnection.Size = new System.Drawing.Size(450, 125);
            this.grpConnection.TabStop = false;
            this.grpConnection.Text = "连接设置";

            this.lblPort.AutoSize = true;
            this.lblPort.Location = new System.Drawing.Point(15, 27);
            this.lblPort.Text = "串口:";

            this.comboBoxPort.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.comboBoxPort.Location = new System.Drawing.Point(70, 23);
            this.comboBoxPort.Size = new System.Drawing.Size(150, 25);

            this.btnRefreshPorts.Location = new System.Drawing.Point(230, 22);
            this.btnRefreshPorts.Size = new System.Drawing.Size(90, 27);
            this.btnRefreshPorts.Text = "刷新端口";
            this.btnRefreshPorts.UseVisualStyleBackColor = true;
            this.btnRefreshPorts.Click += new System.EventHandler(this.btnRefreshPorts_Click);

            this.lblBaud.AutoSize = true;
            this.lblBaud.Location = new System.Drawing.Point(15, 63);
            this.lblBaud.Text = "波特率:";

            this.comboBoxBaudRate.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.comboBoxBaudRate.Location = new System.Drawing.Point(70, 59);
            this.comboBoxBaudRate.Size = new System.Drawing.Size(150, 25);
            this.comboBoxBaudRate.Items.AddRange(new object[] { "9600", "115200", "230400", "921600" });
            this.comboBoxBaudRate.SelectedIndex = 1;

            this.btnConnect.Location = new System.Drawing.Point(330, 22);
            this.btnConnect.Size = new System.Drawing.Size(95, 62);
            this.btnConnect.Text = "连接";
            this.btnConnect.UseVisualStyleBackColor = true;
            this.btnConnect.Click += new System.EventHandler(this.btnConnect_Click);

            this.lblConnState.AutoSize = false;
            this.lblConnState.Location = new System.Drawing.Point(230, 90);
            this.lblConnState.Size = new System.Drawing.Size(195, 20);
            this.lblConnState.Text = "未连接";
            this.lblConnState.ForeColor = System.Drawing.Color.DimGray;

            this.lblRateNote.AutoSize = false;
            this.lblRateNote.Location = new System.Drawing.Point(12, 90);
            this.lblRateNote.Size = new System.Drawing.Size(212, 28);
            this.lblRateNote.Font = new System.Drawing.Font("微软雅黑", 7.5F);
            this.lblRateNote.ForeColor = System.Drawing.Color.Gray;
            this.lblRateNote.Text = "速率由 FPGA 拨码决定，\r\n选错会解析失败。";

            this.grpConnection.Controls.Add(this.lblPort);
            this.grpConnection.Controls.Add(this.comboBoxPort);
            this.grpConnection.Controls.Add(this.btnRefreshPorts);
            this.grpConnection.Controls.Add(this.lblBaud);
            this.grpConnection.Controls.Add(this.comboBoxBaudRate);
            this.grpConnection.Controls.Add(this.btnConnect);
            this.grpConnection.Controls.Add(this.lblConnState);
            this.grpConnection.Controls.Add(this.lblRateNote);

            // ---- 实时数据 ----
            this.grpLive.Location = new System.Drawing.Point(490, 10);
            this.grpLive.Size = new System.Drawing.Size(430, 125);
            this.grpLive.TabStop = false;
            this.grpLive.Text = "实时数据";

            this.lblDistCap.AutoSize = true;
            this.lblDistCap.Location = new System.Drawing.Point(15, 24);
            this.lblDistCap.Text = "距离:";

            this.lblDistanceValue.AutoSize = false;
            this.lblDistanceValue.Location = new System.Drawing.Point(85, 10);
            this.lblDistanceValue.Size = new System.Drawing.Size(330, 40);
            this.lblDistanceValue.Font = new System.Drawing.Font("微软雅黑", 20F, System.Drawing.FontStyle.Bold);
            this.lblDistanceValue.ForeColor = System.Drawing.Color.RoyalBlue;
            this.lblDistanceValue.Text = "---";

            this.lblIntCap.AutoSize = true;
            this.lblIntCap.Location = new System.Drawing.Point(15, 60);
            this.lblIntCap.Text = "强度:";

            this.lblIntensityValue.AutoSize = false;
            this.lblIntensityValue.Location = new System.Drawing.Point(85, 57);
            this.lblIntensityValue.Size = new System.Drawing.Size(330, 24);
            this.lblIntensityValue.Font = new System.Drawing.Font("微软雅黑", 12F);
            this.lblIntensityValue.ForeColor = System.Drawing.Color.SeaGreen;
            this.lblIntensityValue.Text = "---";

            this.lblAmbCap.AutoSize = true;
            this.lblAmbCap.Location = new System.Drawing.Point(15, 92);
            this.lblAmbCap.Text = "环境光:";

            this.lblAmbientValue.AutoSize = false;
            this.lblAmbientValue.Location = new System.Drawing.Point(85, 89);
            this.lblAmbientValue.Size = new System.Drawing.Size(330, 24);
            this.lblAmbientValue.Font = new System.Drawing.Font("微软雅黑", 12F);
            this.lblAmbientValue.ForeColor = System.Drawing.Color.DarkOrange;
            this.lblAmbientValue.Text = "---";

            this.grpLive.Controls.Add(this.lblDistCap);
            this.grpLive.Controls.Add(this.lblDistanceValue);
            this.grpLive.Controls.Add(this.lblIntCap);
            this.grpLive.Controls.Add(this.lblIntensityValue);
            this.grpLive.Controls.Add(this.lblAmbCap);
            this.grpLive.Controls.Add(this.lblAmbientValue);

            // ---- 链路诊断 ----
            this.grpDiag.Location = new System.Drawing.Point(940, 10);
            this.grpDiag.Size = new System.Drawing.Size(400, 125);
            this.grpDiag.TabStop = false;
            this.grpDiag.Text = "链路诊断";

            this.lblDiag.AutoSize = false;
            this.lblDiag.Location = new System.Drawing.Point(10, 18);
            this.lblDiag.Size = new System.Drawing.Size(380, 102);
            this.lblDiag.Font = new System.Drawing.Font("微软雅黑", 8.5F);
            this.lblDiag.Text = "链路: —    CRC: —\r\n帧计数: —    收字节: —\r\n行率: —    模块帧率: —\r\nU 档位: —    字节/帧: —\r\n模块链路: 921600 8N1（FPGA 固定）";

            this.grpDiag.Controls.Add(this.lblDiag);

            // ---- 曲线 ----
            this.grpChart.Location = new System.Drawing.Point(20, 140);
            this.grpChart.Size = new System.Drawing.Size(960, 370);
            this.grpChart.TabStop = false;
            this.grpChart.Text = "曲线";
            this.grpChart.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;

            this.chkDistance.AutoSize = true;
            this.chkDistance.Location = new System.Drawing.Point(15, 22);
            this.chkDistance.Checked = true;
            this.chkDistance.Text = "距离";
            this.chkDistance.CheckedChanged += new System.EventHandler(this.chkSeries_CheckedChanged);

            this.chkIntensity.AutoSize = true;
            this.chkIntensity.Location = new System.Drawing.Point(100, 22);
            this.chkIntensity.Checked = true;
            this.chkIntensity.Text = "强度";
            this.chkIntensity.CheckedChanged += new System.EventHandler(this.chkSeries_CheckedChanged);

            this.chkAmbient.AutoSize = true;
            this.chkAmbient.Location = new System.Drawing.Point(185, 22);
            this.chkAmbient.Checked = false;
            this.chkAmbient.Text = "环境光";
            this.chkAmbient.CheckedChanged += new System.EventHandler(this.chkSeries_CheckedChanged);

            this.lblWindow.AutoSize = true;
            this.lblWindow.Location = new System.Drawing.Point(290, 24);
            this.lblWindow.Text = "时间窗:";

            this.comboBoxWindow.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.comboBoxWindow.Location = new System.Drawing.Point(350, 20);
            this.comboBoxWindow.Size = new System.Drawing.Size(90, 25);
            this.comboBoxWindow.Items.AddRange(new object[] { "10 秒", "30 秒", "60 秒", "300 秒" });
            this.comboBoxWindow.SelectedIndex = 1;
            this.comboBoxWindow.SelectedIndexChanged += new System.EventHandler(this.comboBoxWindow_SelectedIndexChanged);

            this.btnClearChart.Location = new System.Drawing.Point(620, 18);
            this.btnClearChart.Size = new System.Drawing.Size(100, 32);
            this.btnClearChart.Text = "清空曲线";
            this.btnClearChart.UseVisualStyleBackColor = true;
            this.btnClearChart.Click += new System.EventHandler(this.btnClearChart_Click);

            this.btnSaveCsv.Location = new System.Drawing.Point(730, 18);
            this.btnSaveCsv.Size = new System.Drawing.Size(100, 32);
            this.btnSaveCsv.Text = "保存 CSV";
            this.btnSaveCsv.UseVisualStyleBackColor = true;
            this.btnSaveCsv.Click += new System.EventHandler(this.btnSaveCsv_Click);

            this.btnSavePng.Location = new System.Drawing.Point(840, 18);
            this.btnSavePng.Size = new System.Drawing.Size(100, 32);
            this.btnSavePng.Text = "保存 PNG";
            this.btnSavePng.UseVisualStyleBackColor = true;
            this.btnSavePng.Click += new System.EventHandler(this.btnSavePng_Click);

            this.chartDistance.Location = new System.Drawing.Point(15, 58);
            this.chartDistance.Size = new System.Drawing.Size(930, 300);
            this.chartDistance.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom
                | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;

            this.grpChart.Controls.Add(this.chkDistance);
            this.grpChart.Controls.Add(this.chkIntensity);
            this.grpChart.Controls.Add(this.chkAmbient);
            this.grpChart.Controls.Add(this.lblWindow);
            this.grpChart.Controls.Add(this.comboBoxWindow);
            this.grpChart.Controls.Add(this.btnClearChart);
            this.grpChart.Controls.Add(this.btnSaveCsv);
            this.grpChart.Controls.Add(this.btnSavePng);
            this.grpChart.Controls.Add(this.chartDistance);

            // ---- 会话统计 ----
            this.grpStats.Location = new System.Drawing.Point(1000, 140);
            this.grpStats.Size = new System.Drawing.Size(320, 370);
            this.grpStats.TabStop = false;
            this.grpStats.Text = "会话统计";
            this.grpStats.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;

            this.lblStats.AutoSize = false;
            this.lblStats.Location = new System.Drawing.Point(15, 25);
            this.lblStats.Size = new System.Drawing.Size(290, 335);
            this.lblStats.Font = new System.Drawing.Font("微软雅黑", 10F);
            this.lblStats.Text = "样本数 N: 0\r\n均值: —\r\n标准差 σ: —\r\n最小值: —\r\n最大值: —\r\n峰值差: —\r\n\r\n说明：\r\nσ 为总体标准差（除以 N）；\r\n只统计有效距离样本。";

            this.grpStats.Controls.Add(this.lblStats);

            // ---- 日志 ----
            this.grpLog.Location = new System.Drawing.Point(20, 520);
            this.grpLog.Size = new System.Drawing.Size(1300, 130);
            this.grpLog.TabStop = false;
            this.grpLog.Text = "日志";
            this.grpLog.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom
                | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;

            this.txtLog.Location = new System.Drawing.Point(10, 20);
            this.txtLog.Size = new System.Drawing.Size(1190, 100);
            this.txtLog.Multiline = true;
            this.txtLog.ReadOnly = true;
            this.txtLog.ScrollBars = System.Windows.Forms.ScrollBars.Vertical;
            this.txtLog.Font = new System.Drawing.Font("微软雅黑", 8.5F);
            this.txtLog.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom
                | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;

            this.btnClearLog.Location = new System.Drawing.Point(1210, 20);
            this.btnClearLog.Size = new System.Drawing.Size(80, 32);
            this.btnClearLog.Text = "清空日志";
            this.btnClearLog.UseVisualStyleBackColor = true;
            this.btnClearLog.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            this.btnClearLog.Click += new System.EventHandler(this.btnClearLog_Click);

            this.grpLog.Controls.Add(this.txtLog);
            this.grpLog.Controls.Add(this.btnClearLog);

            // ---- 加入窗体 ----
            this.Controls.Add(this.grpConnection);
            this.Controls.Add(this.grpLive);
            this.Controls.Add(this.grpDiag);
            this.Controls.Add(this.grpChart);
            this.Controls.Add(this.grpStats);
            this.Controls.Add(this.grpLog);

            this.ResumeLayout(false);
        }
    }
}
