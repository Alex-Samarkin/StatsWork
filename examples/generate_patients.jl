"""
Генератор синтетического медицинского датасета пациентов.
Все показатели физиологически связаны: пол → рост/вес → ИМТ → давление → лабораторные нормы.
"""

using Random, CSV, DataFrames, Distributions, Printf

# ──────────────────────────────────────────────
# 1. ИМЕНА
# ──────────────────────────────────────────────
const SURNAMES_M = [
    "Иванов","Смирнов","Кузнецов","Попов","Васильев","Петров","Соколов","Михайлов",
    "Новиков","Фёдоров","Морозов","Волков","Алексеев","Лебедев","Семёнов","Егоров",
    "Павлов","Козлов","Степанов","Николаев","Орлов","Андреев","Макаров","Никитин",
    "Захаров","Зайцев","Соловьёв","Борисов","Яковлев","Григорьев","Романов","Воробьёв",
    "Сергеев","Кузьмин","Фролов","Александров","Дмитриев","Королёв","Гусев","Ильин",
]
const SURNAMES_F = replace.(SURNAMES_M, "ов" => "ова", "ев" => "ева", "ин" => "ина",
                             "ий" => "ая", "ый" => "ая")  # упрощённо
# Точнее вручную:
const SURNAMES_F2 = [
    "Иванова","Смирнова","Кузнецова","Попова","Васильева","Петрова","Соколова","Михайлова",
    "Новикова","Фёдорова","Морозова","Волкова","Алексеева","Лебедева","Семёнова","Егорова",
    "Павлова","Козлова","Степанова","Николаева","Орлова","Андреева","Макарова","Никитина",
    "Захарова","Зайцева","Соловьёва","Борисова","Яковлева","Григорьева","Романова","Воробьёва",
    "Сергеева","Кузьмина","Фролова","Александрова","Дмитриева","Королёва","Гусева","Ильина",
]
const NAMES_M = ["Александр","Дмитрий","Максим","Сергей","Андрей","Алексей","Артём",
                  "Илья","Кирилл","Михаил","Никита","Матвей","Роман","Егор","Арсений",
                  "Иван","Денис","Евгений","Даниил","Тимур","Владимир","Павел","Антон","Фёдор"]
const NAMES_F = ["Анастасия","Мария","Анна","Виктория","Екатерина","Наталья","Марина",
                  "Ольга","Татьяна","Юлия","Ирина","Елена","Дарья","Светлана","Людмила",
                  "Ксения","Алина","Вера","Надежда","Полина","Валентина","Тамара","Галина","Лариса"]
const PATRS_M  = ["Александрович","Дмитриевич","Сергеевич","Андреевич","Алексеевич",
                  "Михайлович","Николаевич","Иванович","Владимирович","Петрович","Юрьевич","Павлович"]
const PATRS_F  = ["Александровна","Дмитриевна","Сергеевна","Андреевна","Алексеевна",
                  "Михайловна","Николаевна","Ивановна","Владимировна","Петровна","Юрьевна","Павловна"]

# ──────────────────────────────────────────────
# 2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ──────────────────────────────────────────────

"""Нормальное распределение, зажатое в [lo, hi] (rejective sampling)."""
function clamp_normal(μ, σ, lo, hi; rng=Random.default_rng())
    for _ in 1:200
        v = μ + σ * randn(rng)
        lo ≤ v ≤ hi && return v
    end
    return clamp(μ, lo, hi)
end

round2(x) = round(x; digits=2)
round1(x) = round(x; digits=1)
roundi(x) = round(Int, x)

# ──────────────────────────────────────────────
# 3. ГЕНЕРАЦИЯ ОДНОГО ПАЦИЕНТА
# ──────────────────────────────────────────────
function generate_patient(id::Int; rng=Random.default_rng())

    # ── Демография ──────────────────────────────
    is_male = rand(rng, Bool)
    sex_str  = is_male ? "М" : "Ж"
    age      = roundi(clamp_normal(45, 18, 18, 85; rng))

    surname   = is_male ? rand(rng, SURNAMES_M)  : rand(rng, SURNAMES_F2)
    firstname = is_male ? rand(rng, NAMES_M)     : rand(rng, NAMES_F)
    patronym  = is_male ? rand(rng, PATRS_M)     : rand(rng, PATRS_F)

    # ── Антропометрия ────────────────────────────
    # Рост: мужчины 170-182, женщины 158-170; небольшая возрастная усадка после 50
    age_shrink = max(0.0, (age - 50) * 0.05)   # см
    height_cm  = if is_male
        clamp_normal(176.0 - age_shrink, 7.0, 155.0, 200.0; rng)
    else
        clamp_normal(163.5 - age_shrink, 6.5, 145.0, 185.0; rng)
    end

    # Вес: нормальный ИМТ 18.5-24.9 с хвостом в лёгкий избыток
    target_bmi = clamp_normal(23.5, 2.8, 17.5, 31.0; rng)
    h_m        = height_cm / 100.0
    weight_kg  = target_bmi * h_m^2
    bmi        = weight_kg / h_m^2   # = target_bmi

    # ── Давление ─────────────────────────────────
    # Базовое АД зависит от возраста и пола
    sbp_base = 110.0 + age * 0.45 + (is_male ? 5.0 : 0.0)
    dbp_base =  70.0 + age * 0.15 + (is_male ? 3.0 : 0.0)
    sbp = roundi(clamp_normal(sbp_base, 8.0, 90.0, 160.0; rng))
    dbp = roundi(clamp_normal(dbp_base, 5.0, 55.0, 100.0; rng))
    # Убедимся, что пульсовое давление ≥ 25
    dbp = min(dbp, sbp - 25)

    pulse = roundi(clamp_normal(72.0, 10.0, 50.0, 110.0; rng))

    # ── Температура тела ─────────────────────────
    temp = round2(clamp_normal(36.6, 0.25, 36.0, 37.2; rng))

    # ── Общий анализ крови ───────────────────────
    # Гемоглобин: м 130-170, ж 120-150 г/л
    hgb_μ = is_male ? 150.0 : 135.0
    hgb   = round1(clamp_normal(hgb_μ, 10.0,
                                is_male ? 130.0 : 120.0,
                                is_male ? 170.0 : 150.0; rng))

    # Эритроциты (×10¹²/л): м 4.2-5.5, ж 3.8-5.1
    rbc_μ = is_male ? 4.85 : 4.45
    rbc   = round2(clamp_normal(rbc_μ, 0.25,
                                is_male ? 4.2 : 3.8,
                                is_male ? 5.5 : 5.1; rng))

    # MCV (фл) — связан с Hgb/RBC примерно
    mcv = round1(clamp_normal(89.0, 5.0, 78.0, 100.0; rng))

    # Лейкоциты (×10⁹/л) 4.0-9.0
    wbc = round2(clamp_normal(6.0, 1.2, 4.0, 9.0; rng))

    # Нейтрофилы % 45-70
    neut_pct = round1(clamp_normal(60.0, 7.0, 45.0, 70.0; rng))
    # Лимфоциты % ~20-40 (оставшееся после нейтрофилов упрощённо)
    lymph_pct = round1(clamp_normal(100.0 - neut_pct - 8.0, 5.0,
                                     max(18.0, 100.0-neut_pct-25.0),
                                     min(40.0, 100.0-neut_pct-3.0); rng))

    # Тромбоциты (×10⁹/л) 150-400
    plt = roundi(clamp_normal(250.0, 50.0, 150.0, 400.0; rng))

    # СОЭ (мм/ч): м ≤15, ж ≤20; растёт с возрастом
    esr_μ  = (is_male ? 8.0 : 12.0) + age * 0.08
    esr_hi = is_male ? 20.0 : 25.0
    esr    = roundi(clamp_normal(esr_μ, 3.5, 1.0, esr_hi; rng))

    # ── Биохимия крови ───────────────────────────
    # Глюкоза натощак (ммоль/л) 3.9-5.5; растёт чуть с возрастом
    glucose_μ = 4.8 + age * 0.008
    glucose = round2(clamp_normal(glucose_μ, 0.4, 3.9, 5.8; rng))

    # Холестерин общий (ммоль/л) 3.1-5.2
    chol_μ = 4.5 + age * 0.012 + (is_male ? 0.1 : -0.1)
    chol   = round2(clamp_normal(chol_μ, 0.5, 3.1, 5.9; rng))

    # ЛПВП (ммоль/л): м 0.9-1.7, ж 1.0-2.0
    hdl_μ = is_male ? 1.2 : 1.5
    hdl   = round2(clamp_normal(hdl_μ, 0.2,
                                is_male ? 0.9 : 1.0,
                                is_male ? 1.7 : 2.0; rng))

    # ЛПНП (ммоль/л) — расчётное, но с шумом
    ldl = round2(clamp_normal(chol - hdl - 0.9, 0.4, 1.5, 4.2; rng))

    # Триглицериды (ммоль/л) 0.5-2.0
    tg = round2(clamp_normal(1.2, 0.35, 0.5, 2.2; rng))

    # Мочевина (ммоль/л) 2.5-8.3
    urea = round2(clamp_normal(5.5, 1.2, 2.5, 8.3; rng))

    # Креатинин (мкмоль/л): м 62-115, ж 44-97
    crea_μ = is_male ? 90.0 : 72.0
    crea   = round1(clamp_normal(crea_μ, 12.0,
                                  is_male ? 62.0 : 44.0,
                                  is_male ? 115.0 : 97.0; rng))

    # АЛТ (Ед/л): м ≤40, ж ≤35
    alt_hi = is_male ? 40.0 : 35.0
    alt    = round1(clamp_normal(alt_hi * 0.55, alt_hi * 0.2, 5.0, alt_hi; rng))

    # АСТ (Ед/л): м ≤40, ж ≤35
    ast    = round1(clamp_normal(alt_hi * 0.50, alt_hi * 0.2, 5.0, alt_hi; rng))

    # ── Общий анализ мочи ────────────────────────
    # pH мочи 4.5-8.0
    urine_ph = round1(clamp_normal(6.0, 0.6, 4.5, 8.0; rng))

    # Удельный вес 1005-1025
    urine_sg = round(clamp_normal(1015.0, 4.0, 1005.0, 1025.0; rng); digits=0)

    # Белок в моче (г/л) — норма ≤0.033, большинство 0.0
    urine_protein = rand(rng) < 0.85 ? 0.0 : round2(clamp_normal(0.02, 0.008, 0.005, 0.033; rng))

    # Лейкоциты в моче (в п/зр): норма м ≤3, ж ≤5
    urine_wbc_hi = is_male ? 3 : 5
    urine_wbc_urine = roundi(clamp_normal(1.0, 0.8, 0.0, Float64(urine_wbc_hi); rng))

    # ── Пульсоксиметрия ──────────────────────────
    spo2 = roundi(clamp_normal(98.0, 1.0, 95.0, 100.0; rng))

    # ──────────────────────────────────────────────
    return (
        id             = id,
        surname        = surname,
        firstname      = firstname,
        patronym       = patronym,
        sex            = sex_str,
        age            = age,
        height_cm      = round1(height_cm),
        weight_kg      = round1(weight_kg),
        bmi            = round2(bmi),
        sbp_mmhg       = sbp,
        dbp_mmhg       = dbp,
        pulse_bpm      = pulse,
        temp_c         = temp,
        spo2_pct       = spo2,
        hgb_gL         = hgb,
        rbc_e12        = rbc,
        mcv_fl         = mcv,
        wbc_e9         = wbc,
        neut_pct       = neut_pct,
        lymph_pct      = lymph_pct,
        plt_e9         = plt,
        esr_mmh        = esr,
        glucose_mmolL  = glucose,
        chol_mmolL     = chol,
        hdl_mmolL      = hdl,
        ldl_mmolL      = ldl,
        tg_mmolL       = tg,
        urea_mmolL     = urea,
        creatinine_umL = crea,
        alt_UL         = alt,
        ast_UL         = ast,
        urine_ph       = urine_ph,
        urine_sg       = Int(urine_sg),
        urine_protein_gL = urine_protein,
        urine_wbc_hpf  = urine_wbc_urine,
    )
end

# ──────────────────────────────────────────────
# 4. MAIN
# ──────────────────────────────────────────────
function main()
    n      = parse(Int, get(ENV, "N_PATIENTS", "3500"))
    seed   = parse(Int, get(ENV, "SEED",       "42"))
    # outdir = get(ENV, "OUTDIR", "/mnt/user-data/outputs")
    outdir = "./examples"

    rng = MersenneTwister(seed)

    println("Генерация $n пациентов (seed=$seed) …")
    rows = [generate_patient(i; rng) for i in 1:n]
    df   = DataFrame(rows)

    # ── Краткая QC-статистика ─────────────────
    println("\n─── QC: выборочные диапазоны ───")
    for col in [:height_cm, :weight_kg, :bmi, :sbp_mmhg, :glucose_mmolL,
                :hgb_gL, :wbc_e9, :creatinine_umL]
        v = df[!, col]
        @printf("  %-22s  min=%6.1f  mean=%6.1f  max=%6.1f\n",
                string(col), minimum(v), mean(v), maximum(v))
    end
    println("  Пол: М=$(count(==("М"), df.sex))  Ж=$(count(==("Ж"), df.sex))")

    # ── Сохранение ───────────────────────────
    outpath = joinpath(outdir, "patients_$(n).csv")
    CSV.write(outpath, df)
    println("\n✓ Сохранено: $outpath  ($(nrow(df)) строк × $(ncol(df)) колонок)")
end

main()
