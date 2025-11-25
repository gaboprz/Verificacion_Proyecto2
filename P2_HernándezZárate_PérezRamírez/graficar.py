import matplotlib.pyplot as plt

def procesar_archivo(nombre_archivo):
    with open(nombre_archivo, 'r') as archivo:
        lineas = archivo.readlines()
    
    # Buscar el inicio de la sección de latencia
    inicio = -1
    for i, linea in enumerate(lineas):
        if "AVERAGE LATENCY PER TERMINAL" in linea:
            inicio = i + 2  # Saltar línea de título y encabezado
            break
    
    if inicio == -1:
        raise ValueError("No se encontró la sección de latencia en el archivo")
    
    # Extraer datos de las terminales
    terminales = []
    latencias = []
    
    for i in range(inicio, inicio + 20):  # Buscar en un rango amplio
        if i >= len(lineas):
            break
            
        linea = lineas[i].strip()
        if not linea:
            continue
            
        # Verificar si es una línea de datos de terminal
        if "Terminal_" in linea and "," in linea:
            # Dividir por comas
            partes = linea.split(",")
            if len(partes) >= 2:
                try:
                    terminal = partes[0].strip()
                    latencia = int(partes[1].strip())
                    terminales.append(terminal)
                    latencias.append(latencia)
                except (ValueError, IndexError):
                    continue
    
    return terminales, latencias

def generar_grafico(terminales, latencias):
    if not terminales:
        print("No se encontraron datos para graficar")
        return
        
    plt.figure(figsize=(14, 7))
    bars = plt.bar(terminales, latencias, color='lightblue', edgecolor='navy', alpha=0.7)
    plt.title('Latencia Promedio por Terminal', fontsize=16, fontweight='bold', pad=20)
    plt.xlabel('Terminal', fontsize=12, fontweight='bold')
    plt.ylabel('Latencia (ms)', fontsize=12, fontweight='bold')
    plt.xticks(rotation=45, ha='right')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    
    # Añadir valores en las barras
    for bar, latencia in zip(bars, latencias):
        plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 2, 
                str(latencia), ha='center', va='bottom', fontweight='bold', fontsize=10)
    
    # Destacar la terminal con mayor y menor latencia
    if latencias:
        max_latencia_idx = latencias.index(max(latencias))
        min_latencia_idx = latencias.index(min(latencias))
        
        bars[max_latencia_idx].set_color('lightcoral')
        bars[min_latencia_idx].set_color('lightgreen')
        
        # Añadir leyenda
        plt.text(0.02, 0.98, f'Mayor latencia: {terminales[max_latencia_idx]} ({max(latencias)} ms)', 
                transform=plt.gca().transAxes, fontsize=10, verticalalignment='top',
                bbox=dict(boxstyle='round', facecolor='lightcoral', alpha=0.7))
        plt.text(0.02, 0.92, f'Menor latencia: {terminales[min_latencia_idx]} ({min(latencias)} ms)', 
                transform=plt.gca().transAxes, fontsize=10, verticalalignment='top',
                bbox=dict(boxstyle='round', facecolor='lightgreen', alpha=0.7))
    
    plt.tight_layout()
    plt.show()

# Uso del código
if __name__ == "__main__":
    nombre_archivo = "scoreboard_report.csv"  # Cambia por el nombre real de tu archivo
    
    try:
        terminales, latencias = procesar_archivo(nombre_archivo)
        
        print(f"Se encontraron {len(terminales)} terminales:")
        for t, l in zip(terminales, latencias):
            print(f"  {t}: {l} ms")
        
        if terminales:
            print(f"\nLatencia máxima: {max(latencias)} ms")
            print(f"Latencia mínima: {min(latencias)} ms")
            print(f"Latencia promedio: {sum(latencias)/len(latencias):.2f} ms")
        
        generar_grafico(terminales, latencias)
        
    except FileNotFoundError:
        print(f"Error: No se encontró el archivo '{nombre_archivo}'")
    except Exception as e:
        print(f"Error: {e}")