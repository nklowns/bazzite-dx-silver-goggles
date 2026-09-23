#!/usr/bin/env bash
# ==============================================================================
# Bazzite-DX Silver Goggles: Dell G15 Thermal Validation & Burn-in Benchmark
# Measures PTM7950 phase-change behavior, core-to-core deltas, and throttling.
# ==============================================================================
set -euo pipefail

MODE="${1:-full}"
if [[ "$MODE" == "quick" ]]; then
	HEAT_SECS="${HEAT_SECS:-15}"
	COOL_SECS="${COOL_SECS:-10}"
	STRESS_SECS="${STRESS_SECS:-15}"
else
	HEAT_SECS="${HEAT_SECS:-300}"
	COOL_SECS="${COOL_SECS:-180}"
	STRESS_SECS="${STRESS_SECS:-180}"
fi

# --- Find hwmon paths dynamically (order-independent) ---
CORETEMP_DIR=""
ALIENWARE_DIR=""
for h in /sys/class/hwmon/hwmon*; do
	[ -d "$h" ] || continue
	name=""
	if [ -r "$h/name" ]; then
		read -r name <"$h/name"
	else
		continue
	fi
	case "$name" in
	coretemp) CORETEMP_DIR="$h" ;;
	alienware_wmi) ALIENWARE_DIR="$h" ;;
	esac
done

if [[ -z "$CORETEMP_DIR" ]]; then
	echo "❌ Erro: Sensor coretemp não encontrado em /sys/class/hwmon/" >&2
	exit 1
fi

# --- Helper functions ---
get_core_temp() {
	local label="$1"
	for t in "$CORETEMP_DIR"/temp*_input; do
		local base="${t%_input}"
		local lbl=""
		[ -r "${base}_label" ] && read -r lbl <"${base}_label"
		if [[ "$lbl" == "$label" ]]; then
			local val
			read -r val <"$t"
			echo "$((val / 1000))"
			return 0
		fi
	done
	echo "0"
}

get_throttle_count() {
	local count=0
	if [[ -r /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count ]]; then
		read -r count </sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count
	fi
	echo "$count"
}

get_fans() {
	local cpu_fan=0 gpu_fan=0
	if [[ -n "$ALIENWARE_DIR" ]]; then
		[ -r "$ALIENWARE_DIR/fan1_input" ] && read -r cpu_fan <"$ALIENWARE_DIR/fan1_input" || true
		[ -r "$ALIENWARE_DIR/fan2_input" ] && read -r gpu_fan <"$ALIENWARE_DIR/fan2_input" || true
	fi
	echo "${cpu_fan:-0} ${gpu_fan:-0}"
}

get_gpu_metrics() {
	nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>/dev/null |
		awk -F', ' '{printf "%d %d %d", $1, $2, $3}' || echo "0 0 0"
}

set_profile() {
	local target="$1"
	echo "⚡ Ajustando perfil Dell G15 para: $target..."
	if command -v busctl >/dev/null 2>&1; then
		busctl set-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile s "$target" 2>/dev/null || true
	fi
	sleep 2
}

# --- Telemetry Sampler ---
# Samples CPU, GPU, Core Delta, Fans and Throttle events
sample_metrics() {
	local pkg_temp
	pkg_temp=$(get_core_temp "Package id 0")

	# P-Cores on i7-12700H (Cores 0, 4, 8, 12, 16, 20)
	local p0 p4 p8 p12 p16 p20
	p0=$(get_core_temp "Core 0")
	p4=$(get_core_temp "Core 4")
	p8=$(get_core_temp "Core 8")
	p12=$(get_core_temp "Core 12")
	p16=$(get_core_temp "Core 16")
	p20=$(get_core_temp "Core 20")

	# Compute Core Delta (max - min among P-Cores)
	local p_temps=("$p0" "$p4" "$p8" "$p12" "$p16" "$p20")
	local min_p=999 max_p=0
	for t in "${p_temps[@]}"; do
		((t > 0 && t < min_p)) && min_p=$t
		((t > max_p)) && max_p=$t
	done
	local delta_p=$((max_p - min_p))
	((delta_p < 0)) && delta_p=0

	# GPU and Fans
	read -r gpu_temp gpu_watts _ <<<"$(get_gpu_metrics)"
	read -r cpu_fan gpu_fan <<<"$(get_fans)"
	local th_count
	th_count=$(get_throttle_count)

	echo "$pkg_temp $min_p $max_p $delta_p $gpu_temp $gpu_watts $cpu_fan $gpu_fan $th_count"
}

# --- Phase Runner ---
run_phase() {
	local name="$1"
	local duration="$2"
	local is_load="$3"
	local stress_pid=""

	echo ""
	echo "======================================================================"
	echo "  FASE: $name (${duration}s)"
	echo "======================================================================"

	local init_throttle
	init_throttle=$(get_throttle_count)

	if [[ "$is_load" == "true" ]]; then
		stress-ng --cpu 0 --cpu-method matrixprod --timeout "${duration}s" >/dev/null 2>&1 &
		stress_pid=$!
	fi

	local elapsed=0
	local max_pkg=0 max_gpu=0 max_delta=0 sum_delta=0 count=0

	printf "%-8s | %-12s | %-12s | %-10s | %-12s | %-10s\n" "Tempo" "CPU Pkg (°C)" "P-Core Delta" "GPU (°C/W)" "Fans (C/G)" "Throttle"
	printf -- "----------------------------------------------------------------------\n"

	while ((elapsed < duration)); do
		sleep 2
		elapsed=$((elapsed + 2))
		count=$((count + 1))

		read -r pkg min_p max_p delta gpu_temp gpu_watts c_fan g_fan cur_th <<<"$(sample_metrics)"

		((pkg > max_pkg)) && max_pkg=$pkg
		((gpu_temp > max_gpu)) && max_gpu=$gpu_temp
		((delta > max_delta)) && max_delta=$delta
		sum_delta=$((sum_delta + delta))

		local new_th=$((cur_th - init_throttle))

		printf "%5ds/%-2ds | %3d°C (%2d-%2d) | %2d°C delta   | %2d°C/%3dW  | %4d/%4d rpm | +%-4d\n" \
			"$elapsed" "$duration" "$pkg" "$min_p" "$max_p" "$delta" "$gpu_temp" "$gpu_watts" "$c_fan" "$g_fan" "$new_th"

		if [[ "$is_load" == "true" ]] && ! kill -0 "$stress_pid" 2>/dev/null; then
			break
		fi
	done

	if [[ -n "$stress_pid" ]] && kill -0 "$stress_pid" 2>/dev/null; then
		wait "$stress_pid" || true
	fi

	local final_th
	final_th=$(($(get_throttle_count) - init_throttle))
	local avg_delta=$((count > 0 ? sum_delta / count : 0))

	echo "----------------------------------------------------------------------"
	echo "  📊 Resumo da Fase: Pkg Máx: ${max_pkg}°C | GPU Máx: ${max_gpu}°C | Delta P-Core Méd/Máx: ${avg_delta}°C/${max_delta}°C | Throttles: +${final_th}"
}

# --- Main Flow ---
echo "======================================================================"
echo "    SILVER GOGGLES: VALIDAÇÃO TÉRMICA HONEYWELL PTM7950 (DELL G15)"
echo "======================================================================"

# Baseline repouso
local_wait=10
[[ "$MODE" == "quick" ]] && local_wait=2
echo "🔍 Medindo baseline inicial em repouso (${local_wait} segundos)..."
sleep "$local_wait"
read -r b_pkg _ _ b_delta b_gpu b_w _ _ _ <<<"$(sample_metrics)"
echo "✅ Baseline: CPU Pkg: ${b_pkg}°C | P-Core Delta: ${b_delta}°C | GPU: ${b_gpu}°C (${b_w}W)"

if [[ "$MODE" == "balanced" || "$MODE" == "full" || "$MODE" == "quick" ]]; then
	set_profile "balanced"
	run_phase "Ciclo 1: Aquecimento PTM7950 (Balanced)" "$HEAT_SECS" "true"
	run_phase "Ciclo 1: Resfriamento e Solidificação (Idle)" "$COOL_SECS" "false"
fi

if [[ "$MODE" == "performance" || "$MODE" == "full" || "$MODE" == "quick" ]]; then
	set_profile "performance"
	run_phase "Ciclo 2: Carga Máxima G-Mode (Performance)" "$HEAT_SECS" "true"
	run_phase "Ciclo 2: Resfriamento Rápido G-Mode (Idle)" "$COOL_SECS" "false"
fi

if [[ "$MODE" == "full" || "$MODE" == "quick" ]]; then
	echo ""
	echo "🔥 Fase Final: Estresse Térmico Combinado (CPU + GPU)"
	set_profile "performance"
	run_phase "Estresse Combinado Sustentado" "$STRESS_SECS" "true"
	# Retornar ao perfil equilibrado do dia a dia
	set_profile "balanced"
fi

echo ""
echo "======================================================================"
echo "  ✅ PROTOCOLO CONCLUÍDO COM SUCESSO!"
echo "======================================================================"
