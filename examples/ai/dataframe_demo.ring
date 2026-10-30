# ====================================================================
#   Madar AI Suite - High-Speed DataFrame & Analytics Demo
#   (عرض محرك جداول البيانات السريع والعمليات الإحصائية المتصلة)
# ====================================================================
load "stdlibCore.ring"
load "dataframe.ring"
load "chronos.ring"

func main {
	? "===================================================================="
	? "  Madar DataFrame: C-Continuous Tensor Table Analytics"
	? "  (تحليل البيانات والجداول بذاكرة C المتصلة وسرعة فائقة)"
	? "===================================================================="

	# 1. Create sample CSV file
	cCSV = "id,name,department,age,salary,performance" + nl +
	       "1,Ahmed,AI Engineering,28,4500,92.5" + nl +
	       "2,Fatima,Data Science,32,5200,95.0" + nl +
	       "3,Ali,DevOps,25,3800,88.0" + nl +
	       "4,Sara,AI Research,29,6100,98.2" + nl +
	       "5,Karim,Frontend,24,3200,84.5" + nl +
	       "6,Youssef,Backend,35,5800,91.0" + nl +
	       "7,Nour,Security,31,4900,93.4" + nl +
	       "8,Omar,AI Engineering,27,4700,89.5" + nl

	cFilePath = "sample_data.csv"
	write(cFilePath, cCSV)

	oTimer = new Chronos()

	? f"Reading CSV into Madar DataFrame: {cFilePath}"
	oTimer.reset()
	oDF = read_csv(cFilePath)
	oTimer.stop()
	? f"  -> Ingested {oDF.nRows} rows and {len(oDF.columns())} columns in {oTimer.elapsed()}"

	see "Columns: "
	for col in oDF.columns() {
		see f" [{col}]"
	}
	? ""

	? nl + "1. Display First 5 Rows (df.head):"
	oDF.head(5)

	? nl + "2. Statistical Summary (df.describe) with C-Tensor Math:"
	oTimer.reset()
	oDF.describe()
	oTimer.stop()
	? f"  [describe computed in {oTimer.elapsed()}]"

	? nl + "3. Filter: Employees with Salary > 4500 (df.filter):"
	oTimer.reset()
	oDFHighSalary = oDF.filter("salary", ">", 4500)
	oTimer.stop()
	oDFHighSalary.head(10)
	? f"  [Filter matched {oDFHighSalary.nRows} records in {oTimer.elapsed()}]"

	? nl + f"Average Salary in High Earners: {oDFHighSalary.mean('salary')} USD"
	? f"Max Performance Score: {oDF.max('performance')}"

	? nl + "===================================================================="
	? "  DataFrame Demo Completed Successfully."
	? "===================================================================="
}
