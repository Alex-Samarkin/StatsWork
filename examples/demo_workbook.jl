using StatsWorkbench
using DataFrames

df = DataFrame(x=1:10, y=rand(10))

wb = open_workbook("Demo")
add_dataset!(wb, :data, df)

println(vars(wb))

close_workbook!(wb)
