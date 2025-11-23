set terminal pngcairo size 1200,800 enhanced font 'Arial,12'
set output 'latency_by_terminal.png'
set title 'Latencia Promedio por Terminal\n(Test con 750 paquetes)' font 'Arial-Bold,14'
set xlabel 'Terminal' font 'Arial-Bold,12'
set ylabel 'Latencia Promedio (ns)' font 'Arial-Bold,12'
set style data histograms
set style histogram cluster gap 1
set style fill solid 0.8 border -1
set boxwidth 0.8
set grid ytics lt 0 lw 1 lc rgb '#DDDDDD'
set grid xtics lt 0 lw 1 lc rgb '#DDDDDD'
set key top right
set xtics 0,1,15
set yrange [0:*]
plot 'latency_data.dat' using 2:xtic(1) title 'Latencia Promedio (ns)' lc rgb '#2E86AB', \
     '' using 0:2:3 with labels offset 0,1 title ''
set output
print 'Gráfico generado: latency_by_terminal.png'
