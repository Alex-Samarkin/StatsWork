using Revise
using StatsWorkbench
using DataFrames

#==============================================
df = DataFrame(x=1:10, y=rand(10))
print(df)
save_data(df, "demo_data.csv")
===============================================#

df = safe_load("./examples/patients_3500.csv")
wb = open_workbook("Demo")
add_dataset!(wb, :data, df)

println(vars(wb))

close_workbook!(wb)
