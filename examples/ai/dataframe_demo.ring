# ====================================================================
#   Madar AI Suite - High-Speed DataFrame & Analytics Demo
#   (عرض محرك جداول البيانات السريع والعمليات الإحصائية المتصلة)
# ====================================================================
load "stdlibCore.ring"
load "dataframe.ring"

see "====================================================================" + nl
see "  Madar DataFrame: C-Continuous Tensor Table Analytics" + nl
see "  (تحليل البيانات والجداول بذاكرة C المتصلة وسرعة فائقة)" + nl
see "====================================================================" + nl

# Create sample CSV file
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

see "Reading CSV into Madar DataFrame: " + cFilePath + nl
df = read_csv(cFilePath)

see "Columns: "
for col in df.columns() see " [" + col + "]" next
see nl

see nl + "1. Display First 5 Rows (df.head):" + nl
df.head(5)

see nl + "2. Statistical Summary (df.describe) with C-Tensor Math:" + nl
df.describe()

see nl + "3. Filter: Employees with Salary > 4500 (df.filter):" + nl
dfHighSalary = df.filter("salary", ">", 4500)
dfHighSalary.head(10)

see nl + "Average Salary in High Earners: " + dfHighSalary.mean("salary") + " USD" + nl
see "Max Performance Score: " + df.max("performance") + nl

see nl + "====================================================================" + nl
see "  DataFrame Demo Completed Successfully." + nl
see "====================================================================" + nl
