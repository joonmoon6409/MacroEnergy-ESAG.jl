library(tidyverse)

# ── 1. 지역별 가중치 (GDP + Population 평균) ──────────────────────────────
province_data <- tribble(
  ~region,  ~gdp_bil_krw,  ~population,
  "SEL",    486986,        9509458,
  "PUS",    105857,        3350380,
  "TAE",     53471,        1453532,
  "INC",    107234,        2948375,
  "KWJ",     40289,        1441970,
  "USN",     77523,        1121592,
  "SJG",     54321,         818632,
  "GGI",    599283,       13565450,
  "GWN",     47823,        1536270,
  "CNA",     82341,        2118663,
  "CNB",     96234,        1596066,
  "DJJ",     49823,         724791,
  "JNB",     75432,        1786855,
  "JNA",     50234,        1820764,
  "GNB",    145623,        2638474,
  "GNA",    116543,        3314183,
  "JEJ",     22341,         676759
)

province_data <- province_data %>%
  mutate(
    gdp_share  = gdp_bil_krw / sum(gdp_bil_krw),
    pop_share  = population  / sum(population),
    weight     = (gdp_share + pop_share) / 2
  )

cat("지역별 가중치:\n")
print(province_data %>% select(region, gdp_share, pop_share, weight))
cat("가중치 합계:", sum(province_data$weight), "\n\n")

# ── 2. 수요 데이터 읽기 ───────────────────────────────────────────────────
demand <- read_csv("demand.csv") %>%
  select(Time_Index, Demand_MW, Demand_MW_25, Demand_MW_30, Demand_MW_35,
         Demand_heat, Demand_Zero)

# ── 3. 전기 수요 지역별 분리 ─────────────────────────────────────────────
for (r in province_data$region) {
  w <- province_data$weight[province_data$region == r]
  demand[[paste0("Demand_MW_",    r)]] <- demand$Demand_MW    * w
  demand[[paste0("Demand_MW_25_", r)]] <- demand$Demand_MW_25 * w
  demand[[paste0("Demand_MW_30_", r)]] <- demand$Demand_MW_30 * w
  demand[[paste0("Demand_MW_35_", r)]] <- demand$Demand_MW_35 * w
}

# ── 4. 열 수요 지역별 분리 ───────────────────────────────────────────────
for (r in province_data$region) {
  w <- province_data$weight[province_data$region == r]
  demand[[paste0("Demand_heat_",    r)]] <- demand$Demand_heat * w
  demand[[paste0("Demand_heat_25_", r)]] <- demand$Demand_heat * w
  demand[[paste0("Demand_heat_30_", r)]] <- demand$Demand_heat * w
  demand[[paste0("Demand_heat_35_", r)]] <- demand$Demand_heat * w
}

# ── 5. 저장 ──────────────────────────────────────────────────────────────
write_csv(demand, "demand_provincial.csv")
cat("완료: demand_provincial.csv 저장됨\n")
cat("컬럼 수:", ncol(demand), "\n")
cat("행 수:",   nrow(demand), "\n")


###################################################

library(tidyverse)

# ── 설정 ──────────────────────────────────────────────────────────────
set.seed(42)

# 계절별 대표일 수 (총 14일 = 336시간)
n_days <- list(
  spring = 3,  # 3~5월
  summer = 4,  # 6~8월 (피크)
  fall   = 3,  # 9~11월
  winter = 4   # 12~2월 (피크)
)

# ── 데이터 읽기 ───────────────────────────────────────────────────────
demand <- read_csv("demand.csv") %>%
  select(where(~!all(is.na(.)))) %>%   # 빈 컬럼 제거
  mutate(across(everything(), ~replace_na(., 0)))  # 혹시 남은 NA → 0

availability <- read_csv("availability.csv") %>%
  select(where(~!all(is.na(.)))) %>%   # 빈 컬럼 제거 (availability_one 등)
  mutate(across(-Time_Index, ~replace_na(., 0)))  # NA → 0

# demand 컬럼 중 대표적인 것으로 클러스터링 (2021 기준)
# provincial demand 전체 합산이 원래 Demand_MW와 같으므로 Demand_MW 사용
df <- demand %>%
  select(Time_Index, Demand_MW) %>%
  left_join(availability %>% select(Time_Index, KR_utilitypv, onwind, `offwind-dc`),
            by = "Time_Index")

# ── 날짜 인덱스 추가 ─────────────────────────────────────────────────
df <- df %>%
  mutate(
    hour_of_day = (Time_Index - 1) %% 24,
    day_index   = (Time_Index - 1) %/% 24 + 1,  # 1~365
    month       = ceiling(day_index / 30.44),     # 근사 월
    month       = pmin(month, 12),
    season      = case_when(
      month %in% 3:5  ~ "spring",
      month %in% 6:8  ~ "summer",
      month %in% 9:11 ~ "fall",
      TRUE            ~ "winter"
    )
  )

# ── 계절별 k-means 클러스터링 ─────────────────────────────────────────
# 각 날을 24시간 프로파일 벡터로 표현 후 클러스터링

get_rep_days <- function(season_name, k) {
  # 해당 계절의 날 추출
  season_days <- df %>%
    filter(season == season_name) %>%
    select(day_index, hour_of_day, Demand_MW, KR_utilitypv, onwind) %>%
    pivot_wider(names_from = hour_of_day,
                values_from = c(Demand_MW, KR_utilitypv, onwind),
                names_sep = "_h")
  
  day_ids <- season_days$day_index
  feature_mat <- season_days %>% select(-day_index) %>% as.matrix()
  
  # 정규화 (분산=0인 컬럼 제거 - 태양광 야간 시간 등)
  col_sd <- apply(feature_mat, 2, sd, na.rm = TRUE)
  feature_mat2 <- feature_mat[, col_sd > 1e-10, drop = FALSE]
  feature_scaled <- scale(feature_mat2)
  feature_scaled[is.nan(feature_scaled)] <- 0
  
  # k-means
  km <- kmeans(feature_scaled, centers = k, nstart = 50, iter.max = 300)
  
  # 각 클러스터에서 센터와 가장 가까운 실제 날 선택
  rep_days <- sapply(1:k, function(cl) {
    cluster_idx <- which(km$cluster == cl)
    if (length(cluster_idx) == 1) return(day_ids[cluster_idx])
    dists <- rowSums((feature_scaled[cluster_idx, , drop=FALSE] -
                        matrix(km$centers[cl,], nrow=length(cluster_idx),
                               ncol=ncol(feature_scaled), byrow=TRUE))^2)
    day_ids[cluster_idx[which.min(dists)]]
  })
  
  # weight: 각 클러스터가 몇 일을 대표하는지
  weights <- table(km$cluster)
  
  tibble(
    season    = season_name,
    day_index = rep_days,
    weight    = as.numeric(weights[order(as.numeric(names(weights)))])
  )
}

rep_days_all <- bind_rows(
  get_rep_days("spring", n_days$spring),
  get_rep_days("summer", n_days$summer),
  get_rep_days("fall",   n_days$fall),
  get_rep_days("winter", n_days$winter)
) %>%
  arrange(day_index) %>%
  mutate(rep_order = row_number())

cat("선택된 대표일:\n")
print(rep_days_all)
cat("\n총 대표일:", nrow(rep_days_all), "일 =", nrow(rep_days_all)*24, "시간\n")
cat("weight 합계:", sum(rep_days_all$weight), "일 (≈365)\n\n")

# ── 대표 시간 인덱스 생성 ─────────────────────────────────────────────
rep_hours <- rep_days_all %>%
  mutate(
    start_hour = (day_index - 1) * 24 + 1,
    hours      = map(start_hour, ~.x:(.x+23))
  ) %>%
  unnest(hours) %>%
  rename(original_Time_Index = hours) %>%
  mutate(new_Time_Index = row_number())

# ── demand_rep.csv 생성 ───────────────────────────────────────────────
demand_rep <- rep_hours %>%
  select(new_Time_Index, original_Time_Index) %>%
  left_join(demand %>% rename(original_Time_Index = Time_Index), 
            by = "original_Time_Index") %>%
  rename(Time_Index = new_Time_Index) %>%
  select(-original_Time_Index)

write_csv(demand_rep, "demand_rep.csv")
cat("demand_rep.csv 저장 완료:", nrow(demand_rep), "행\n")

# ── availability_rep.csv 생성 ─────────────────────────────────────────
availability_rep <- rep_hours %>%
  select(new_Time_Index, original_Time_Index) %>%
  left_join(availability %>% rename(original_Time_Index = Time_Index),
            by = "original_Time_Index") %>%
  rename(Time_Index = new_Time_Index) %>%
  select(-original_Time_Index)

write_csv(availability_rep, "availability_rep.csv")
cat("availability_rep.csv 저장 완료:", nrow(availability_rep), "행\n")

# ── period_map.csv 생성 (MacroEnergy용 time weight) ───────────────────
# 각 representative hour의 weight = 해당 대표일의 weight (일수)
period_map <- rep_hours %>%
  select(Time_Index = new_Time_Index, weight) %>%
  mutate(weight = as.numeric(weight)) %>%
  mutate(weight = weight)  # 단위: 일 (1 rep hour = weight일 × 24h 아님, 1시간 단위)

# MacroEnergy period map: 각 시간이 몇 시간을 대표하는지
# weight는 일 단위이므로 × 24 불필요 (hourly weight = 일수)
write_csv(period_map, "period_map.csv")
cat("period_map.csv 저장 완료\n\n")

# ── time_data_rep.json 생성 ───────────────────────────────────────────
time_data_rep <- list(
  HoursPerSubperiod = list(
    NaturalGas  = 336L,
    Coal        = 336L,
    CO2         = 336L,
    Electricity = 336L,
    Uranium     = 336L,
    Steam       = 336L,
    CO2Captured = 336L
  ),
  HoursPerTimeStep = list(
    NaturalGas  = 1L,
    Coal        = 1L,
    CO2         = 1L,
    Electricity = 1L,
    Uranium     = 1L,
    Steam       = 1L,
    CO2Captured = 1L
  ),
  NumberOfSubperiods = 1L,
  TotalHoursModeled  = 336L,
  PeriodMap = list(path = "system/period_map.csv")
)

jsonlite::write_json(time_data_rep, "time_data_rep.json", 
                     pretty = TRUE, auto_unbox = TRUE)
cat("time_data_rep.json 저장 완료\n")

# ── 요약 플롯 (선택) ──────────────────────────────────────────────────
p <- ggplot(rep_days_all, aes(x = day_index, y = weight, fill = season)) +
  geom_col() +
  scale_fill_manual(values = c(spring="#4CAF50", summer="#FF5722",
                               fall="#FF9800", winter="#2196F3")) +
  labs(title = "Representative Days Selection",
       x = "Day of Year", y = "Weight (days represented)",
       fill = "Season") +
  theme_minimal()

ggsave("rep_days_plot.png", p, width = 10, height = 4)
cat("rep_days_plot.png 저장 완료\n")


############################################################
library(tidyverse)
library(sf)
library(scatterpie)
library(rnaturalearth)
library(rnaturalearthdata)

# ── 1. 색상 ───────────────────────────────────────────────────────────
tech_colors <- c(
  "Coal"          = "#1C1C1C",
  "Natural Gas"   = "#2B6CB0",
  "Nuclear"       = "#DD6B20",
  "CHP"           = "#A0AEC0",
  "Solar"         = "#ECC94B",
  "Onshore Wind"  = "#2B9CC7",
  "Offshore Wind" = "#38A169",
  "Battery"       = "#805AD5"
)
tech_order <- c("Coal","Natural Gas","Nuclear","CHP","Solar","Onshore Wind","Offshore Wind","Battery")

# ── 2. Province 좌표 ──────────────────────────────────────────────────
province_coords <- tribble(
  ~province, ~lon,    ~lat,
  "SEL",     126.978, 37.566,
  "INC",     126.505, 37.456,
  "GGI",     127.300, 37.550,
  "GWN",     128.200, 37.750,
  "DJJ",     127.385, 36.350,
  "SJG",     127.100, 36.600,
  "CNA",     126.600, 36.600,
  "CNB",     127.800, 36.700,
  "JNB",     127.100, 35.700,
  "JNA",     126.700, 34.900,
  "KWJ",     126.852, 35.160,
  "GNB",     128.800, 36.400,
  "TAE",     128.601, 35.870,
  "GNA",     128.300, 35.200,
  "USN",     129.312, 35.540,
  "PUS",     129.075, 35.100,
  "JEJ",     126.530, 33.490
)

name_map <- c(SEL="Seoul",INC="Incheon",GGI="Gyeonggi",GWN="Gangwon",
              DJJ="Daejeon",SJG="Sejong",CNA="Chungnam",CNB="Chungbuk",
              JNB="Jeonbuk",JNA="Jeonnam",KWJ="Gwangju",GNB="Gyeongbuk",
              TAE="Daegu",GNA="Gyeongnam",USN="Ulsan",PUS="Busan",JEJ="Jeju")

# ── 3. Capacity 전처리 ────────────────────────────────────────────────
cap_raw <- read_csv("capacity.csv")
regions  <- province_coords$province

get_province <- function(rid) {
  for (r in regions) {
    if (str_detect(rid, paste0("(?<![A-Z])", r, "(?![A-Z])"))) return(r)
  }
  NA_character_
}

cap <- cap_raw %>%
  filter(variable == "capacity",
         resource_type != "OneWayTransmissionLink{Electricity}") %>%
  mutate(
    province = map_chr(resource_id, get_province),
    tech = case_when(
      str_detect(resource_id, "utility_pv")       ~ "Solar",
      str_detect(resource_id, "onshore_wind")     ~ "Onshore Wind",
      str_detect(resource_id, "offshore_wind")    ~ "Offshore Wind",
      resource_type == "ThermalPower{Coal}"       ~ "Coal",
      resource_type == "ThermalPower{NaturalGas}" ~ "Natural Gas",
      resource_type == "ThermalPower{Uranium}"    ~ "Nuclear",
      str_detect(resource_type, "Steam")          ~ "CHP",
      resource_type == "Battery"                  ~ "Battery",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(province), !is.na(tech), value > 0) %>%
  group_by(province, tech) %>%
  summarise(cap_GW = sum(value) / 1000, .groups = "drop")

cap_wide <- cap %>%
  pivot_wider(names_from = tech, values_from = cap_GW, values_fill = 0) %>%
  left_join(province_coords, by = "province") %>%
  mutate(
    total_GW = rowSums(select(., any_of(tech_order)), na.rm = TRUE),
    radius   = scales::rescale(sqrt(total_GW), to = c(0.12, 0.42)),
    name     = name_map[province]
  )

for (tech in tech_order) {
  if (!tech %in% colnames(cap_wide)) cap_wide[[tech]] <- 0
}

# 큰 원 먼저 그리기 위해 내림차순
cap_wide <- cap_wide %>% arrange(desc(total_GW))

# ── 4. 파이차트용 슬라이스 데이터 (ggforce 없이 직접 polygon) ─────────
# geom_scatterpie 대신 각도 계산 후 geom_polygon으로 직접 그림
# → z-order 완전 제어 가능
make_pie_polygons <- function(df) {
  techs <- tech_order[tech_order %in% names(df %>% select(any_of(tech_order)))]
  result <- list()
  for (i in seq_len(nrow(df))) {
    row    <- df[i, ]
    cx     <- row$lon
    cy     <- row$lat
    r      <- row$radius
    vals   <- as.numeric(row[techs])
    total  <- sum(vals)
    if (total == 0) next
    props  <- vals / total
    angles <- c(0, cumsum(props * 2 * pi))
    for (j in seq_along(techs)) {
      if (props[j] < 1e-6) next
      theta <- seq(angles[j], angles[j+1], length.out = 30)
      px    <- c(cx, cx + r * sin(theta), cx)
      py    <- c(cy, cy + r * cos(theta), cy)
      result[[length(result)+1]] <- tibble(
        x        = px,
        y        = py,
        tech     = techs[j],
        province = row$province,
        group    = paste0(row$province, "_", j)
      )
    }
  }
  bind_rows(result)
}

pie_polys <- make_pie_polygons(cap_wide)

# ── 5. Transmission ───────────────────────────────────────────────────
trans <- tribble(
  ~from,  ~to,    ~cap_MW,
  "SEL",  "INC",  3000, "SEL",  "GGI",  5000,
  "INC",  "GGI",  2000, "GGI",  "GWN",  2500,
  "GGI",  "CNB",  3000, "GGI",  "CNA",  3000,
  "GWN",  "GNB",  2000, "CNB",  "GNB",  2500,
  "CNB",  "JNB",  2000, "CNB",  "DJJ",  2000,
  "CNA",  "DJJ",  2000, "CNA",  "JNB",  1500,
  "SJG",  "CNB",  1000, "SJG",  "CNA",  1000,
  "SJG",  "DJJ",  800,  "GNB",  "TAE",  3000,
  "GNB",  "USN",  2500, "GNB",  "GNA",  3000,
  "TAE",  "GNA",  2500, "USN",  "GNA",  2000,
  "USN",  "PUS",  3000, "GNA",  "PUS",  4000,
  "JNB",  "JNA",  2000, "JNB",  "GNA",  1500,
  "JNA",  "KWJ",  1500, "JNA",  "GNA",  1000,
  "JNA",  "JEJ",  400
) %>%
  left_join(province_coords %>% rename(lon_from=lon,lat_from=lat), by=c("from"="province")) %>%
  left_join(province_coords %>% rename(lon_to=lon,lat_to=lat),   by=c("to"="province")) %>%
  mutate(lw = case_when(
    cap_MW >= 4000 ~ 3.0, cap_MW >= 3000 ~ 2.2,
    cap_MW >= 2000 ~ 1.4, cap_MW >= 1000 ~ 0.7, TRUE ~ 0.35
  ))

# ── 6. 지도 ───────────────────────────────────────────────────────────
korea <- ne_states(country = "South Korea", returnclass = "sf")

# ── 7. 원 크기 범례 데이터 ────────────────────────────────────────────
sqrt_min <- sqrt(min(cap_wide$total_GW))
sqrt_max <- sqrt(max(cap_wide$total_GW))
ref_gw   <- c(5, 15, 30)
ref_r    <- scales::rescale(sqrt(ref_gw), from=c(sqrt_min,sqrt_max), to=c(0.12,0.42))
ref_df   <- tibble(lon=129.25, lat=c(33.35,33.72,34.22), r=ref_r,
                   label=paste0(ref_gw," GW"))

# ── 8. 플롯 ───────────────────────────────────────────────────────────
p <- ggplot() +
  
  # 지도
  geom_sf(data=korea, fill="#EAEDE8", color="white", linewidth=0.6) +
  
  # Transmission
  geom_segment(
    data=trans,
    aes(x=lon_from,y=lat_from,xend=lon_to,yend=lat_to,linewidth=I(lw)),
    color="#2D3748", alpha=0.5, lineend="round"
  ) +
  
  # 파이 — polygon으로 직접 (z-order 제어)
  geom_polygon(
    data=pie_polys,
    aes(x=x, y=y, group=group, fill=tech),
    color="white", linewidth=0.2, alpha=0.93
  ) +
  scale_fill_manual(values=tech_colors, name="Technology",
                    breaks=tech_order[tech_order %in% unique(pie_polys$tech)]) +
  
  # 파이 테두리 원
  geom_point(data=cap_wide, aes(x=lon,y=lat,size=I(radius*115)),
             shape=21, fill=NA, color="white", stroke=0.8, alpha=0.6) +
  
  # Province 라벨
  geom_label(
    data=cap_wide,
    aes(x=lon, y=lat-radius-0.06, label=name),
    size=3.0, label.size=0, fill="white",
    color="#1A202C", fontface="bold", alpha=0.85,
    label.padding=unit(0.12,"lines")
  ) +
  
  # 원 크기 범례 박스
  annotate("rect", xmin=128.7,xmax=130.1, ymin=33.1,ymax=34.65,
           fill="white",color="grey65",alpha=0.9,linewidth=0.4) +
  annotate("text", x=129.4,y=34.50, label="Circle size",
           size=3.0,fontface="bold",color="#1A202C") +
  geom_point(data=ref_df, aes(x=lon,y=lat,size=I(r*50)),
             shape=21,fill="grey78",color="grey50",stroke=0.5,alpha=0.8) +
  geom_text(data=ref_df, aes(x=lon+0.32,y=lat,label=label),
            size=2.6,color="#1A202C",hjust=0) +
  
  # Transmission 더미 선 (범례용)
  geom_segment(
    data=tibble(
      x=125,xend=125,y=33,yend=33,
      cap_label=factor(c("≥4 GW","3 GW","2 GW","1 GW","<1 GW"),
                       levels=c("≥4 GW","3 GW","2 GW","1 GW","<1 GW")),
      lw=c(3.0,2.2,1.4,0.7,0.35)
    ),
    aes(x=x,y=y,xend=xend,yend=yend,linewidth=I(lw),linetype=cap_label),
    color="#2D3748"
  ) +
  scale_linetype_manual(
    values=rep("solid",5), name="Transmission\ncapacity",
    guide=guide_legend(order=1,
                       override.aes=list(linewidth=c(3.0,2.2,1.4,0.7,0.35),color="#2D3748"))
  ) +
  guides(fill=guide_legend(order=2,title="Technology")) +
  
  coord_sf(xlim=c(125.7,130.2), ylim=c(33.0,38.7)) +
  labs(
    title    = "Installed Capacity by Province — 2035",
    subtitle = "NZK Provincial Power Sector Model  |  Circle area ∝ total capacity (GW)",
    caption  = "Source: MacroEnergy optimization results"
  ) +
  theme_void(base_size=12) +
  theme(
    plot.title       = element_text(face="bold",size=15,margin=margin(b=3)),
    plot.subtitle    = element_text(color="grey45",size=10,margin=margin(b=6)),
    plot.caption     = element_text(color="grey55",size=8),
    legend.position  = "right",
    legend.title     = element_text(size=11,face="bold"),
    legend.text      = element_text(size=10),
    legend.spacing.y = unit(4,"pt"),
    plot.margin      = margin(12,12,12,12),
    plot.background  = element_rect(fill="#D6E4F0",color=NA),
    panel.background = element_rect(fill="#D6E4F0",color=NA)
  )

ggsave("capacity_map_2035.png", p, width=11, height=12, dpi=200)
cat("저장 완료: capacity_map_2035.png\n")





#######

library(tidyverse)
library(sf)
library(scatterpie)
library(rnaturalearth)
library(rnaturalearthdata)

# ── 1. 색상 ───────────────────────────────────────────────────────────
tech_colors <- c(
  "Coal"          = "#1C1C1C",
  "Natural Gas"   = "#2B6CB0",
  "Nuclear"       = "#DD6B20",
  "CHP"           = "#A0AEC0",
  "Solar"         = "#ECC94B",
  "Onshore Wind"  = "#2B9CC7",
  "Offshore Wind" = "#38A169",
  "Battery"       = "#805AD5"
)
tech_order <- c("Coal","Natural Gas","Nuclear","CHP","Solar","Onshore Wind","Offshore Wind","Battery")

# ── 2. Province 좌표 ──────────────────────────────────────────────────
province_coords <- tribble(
  ~province, ~lon,    ~lat,
  "SEL",     126.978, 37.566,
  "INC",     126.505, 37.456,
  "GGI",     127.300, 37.550,
  "GWN",     128.200, 37.750,
  "DJJ",     127.385, 36.350,
  "SJG",     127.100, 36.600,
  "CNA",     126.600, 36.600,
  "CNB",     127.800, 36.700,
  "JNB",     127.100, 35.700,
  "JNA",     126.700, 34.900,
  "KWJ",     126.852, 35.160,
  "GNB",     128.800, 36.400,
  "TAE",     128.601, 35.870,
  "GNA",     128.300, 35.200,
  "USN",     129.312, 35.540,
  "PUS",     129.075, 35.100,
  "JEJ",     126.530, 33.490
)

name_map <- c(SEL="Seoul",INC="Incheon",GGI="Gyeonggi",GWN="Gangwon",
              DJJ="Daejeon",SJG="Sejong",CNA="Chungnam",CNB="Chungbuk",
              JNB="Jeonbuk",JNA="Jeonnam",KWJ="Gwangju",GNB="Gyeongbuk",
              TAE="Daegu",GNA="Gyeongnam",USN="Ulsan",PUS="Busan",JEJ="Jeju")

# ── 3. Capacity 전처리 ────────────────────────────────────────────────
cap_raw <- read_csv("capacity.csv")
regions  <- province_coords$province

get_province <- function(rid) {
  for (r in regions) {
    if (str_detect(rid, paste0("(?<![A-Z])", r, "(?![A-Z])"))) return(r)
  }
  NA_character_
}

cap <- cap_raw %>%
  filter(variable == "capacity",
         resource_type != "OneWayTransmissionLink{Electricity}") %>%
  mutate(
    province = map_chr(resource_id, get_province),
    tech = case_when(
      str_detect(resource_id, "utility_pv")       ~ "Solar",
      str_detect(resource_id, "onshore_wind")     ~ "Onshore Wind",
      str_detect(resource_id, "offshore_wind")    ~ "Offshore Wind",
      resource_type == "ThermalPower{Coal}"       ~ "Coal",
      resource_type == "ThermalPower{NaturalGas}" ~ "Natural Gas",
      resource_type == "ThermalPower{Uranium}"    ~ "Nuclear",
      str_detect(resource_type, "Steam")          ~ "CHP",
      resource_type == "Battery"                  ~ "Battery",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(province), !is.na(tech), value > 0) %>%
  group_by(province, tech) %>%
  summarise(cap_GW = sum(value) / 1000, .groups = "drop")

cap_wide <- cap %>%
  pivot_wider(names_from = tech, values_from = cap_GW, values_fill = 0) %>%
  left_join(province_coords, by = "province") %>%
  mutate(
    total_GW = rowSums(select(., any_of(tech_order)), na.rm = TRUE),
    radius   = scales::rescale(sqrt(total_GW), to = c(0.12, 0.42)),
    name     = name_map[province]
  )

for (tech in tech_order) {
  if (!tech %in% colnames(cap_wide)) cap_wide[[tech]] <- 0
}

# 큰 원 먼저 그리기 위해 내림차순
cap_wide <- cap_wide %>% arrange(desc(total_GW))

# ── 4. 파이차트용 슬라이스 데이터 (ggforce 없이 직접 polygon) ─────────
# geom_scatterpie 대신 각도 계산 후 geom_polygon으로 직접 그림
# → z-order 완전 제어 가능
make_pie_polygons <- function(df) {
  techs <- tech_order[tech_order %in% names(df %>% select(any_of(tech_order)))]
  result <- list()
  for (i in seq_len(nrow(df))) {
    row    <- df[i, ]
    cx     <- row$lon
    cy     <- row$lat
    r      <- row$radius
    vals   <- as.numeric(row[techs])
    total  <- sum(vals)
    if (total == 0) next
    props  <- vals / total
    angles <- c(0, cumsum(props * 2 * pi))
    for (j in seq_along(techs)) {
      if (props[j] < 1e-6) next
      theta <- seq(angles[j], angles[j+1], length.out = 30)
      px    <- c(cx, cx + r * sin(theta), cx)
      py    <- c(cy, cy + r * cos(theta), cy)
      result[[length(result)+1]] <- tibble(
        x        = px,
        y        = py,
        tech     = techs[j],
        province = row$province,
        group    = paste0(row$province, "_", j)
      )
    }
  }
  bind_rows(result)
}

pie_polys <- make_pie_polygons(cap_wide)

# ── 5. Transmission ───────────────────────────────────────────────────
trans <- tribble(
  ~from,  ~to,    ~cap_MW,
  "SEL",  "INC",  3000, "SEL",  "GGI",  5000,
  "INC",  "GGI",  2000, "GGI",  "GWN",  2500,
  "GGI",  "CNB",  3000, "GGI",  "CNA",  3000,
  "GWN",  "GNB",  2000, "CNB",  "GNB",  2500,
  "CNB",  "JNB",  2000, "CNB",  "DJJ",  2000,
  "CNA",  "DJJ",  2000, "CNA",  "JNB",  1500,
  "SJG",  "CNB",  1000, "SJG",  "CNA",  1000,
  "SJG",  "DJJ",  800,  "GNB",  "TAE",  3000,
  "GNB",  "USN",  2500, "GNB",  "GNA",  3000,
  "TAE",  "GNA",  2500, "USN",  "GNA",  2000,
  "USN",  "PUS",  3000, "GNA",  "PUS",  4000,
  "JNB",  "JNA",  2000, "JNB",  "GNA",  1500,
  "JNA",  "KWJ",  1500, "JNA",  "GNA",  1000,
  "JNA",  "JEJ",  400
) %>%
  left_join(province_coords %>% rename(lon_from=lon,lat_from=lat), by=c("from"="province")) %>%
  left_join(province_coords %>% rename(lon_to=lon,lat_to=lat),   by=c("to"="province")) %>%
  mutate(lw = case_when(
    cap_MW >= 4000 ~ 3.0, cap_MW >= 3000 ~ 2.2,
    cap_MW >= 2000 ~ 1.4, cap_MW >= 1000 ~ 0.7, TRUE ~ 0.35
  ))

# ── 6. 지도 ───────────────────────────────────────────────────────────
korea <- ne_states(country = "South Korea", returnclass = "sf")

# ── 7. 원 크기 범례 데이터 ────────────────────────────────────────────
sqrt_min <- sqrt(min(cap_wide$total_GW))
sqrt_max <- sqrt(max(cap_wide$total_GW))
ref_gw   <- c(5, 15, 30)
ref_r    <- scales::rescale(sqrt(ref_gw), from=c(sqrt_min,sqrt_max), to=c(0.12,0.42))
ref_df   <- tibble(lon=129.15, lat=c(33.22, 33.65, 34.15), r=ref_r,
                   label=paste0(ref_gw," GW"))

# ── 8. 플롯 ───────────────────────────────────────────────────────────
p <- ggplot() +
  
  # 지도
  geom_sf(data=korea, fill="#EAEDE8", color="white", linewidth=0.6) +
  
  # Transmission
  geom_segment(
    data=trans,
    aes(x=lon_from,y=lat_from,xend=lon_to,yend=lat_to,linewidth=I(lw)),
    color="#2D3748", alpha=0.5, lineend="round"
  ) +
  
  # 파이 — polygon으로 직접 (z-order 제어)
  geom_polygon(
    data=pie_polys,
    aes(x=x, y=y, group=group, fill=tech),
    color="white", linewidth=0.2, alpha=0.93
  ) +
  scale_fill_manual(values=tech_colors, name="Technology",
                    breaks=tech_order[tech_order %in% unique(pie_polys$tech)]) +
  
  # 파이 테두리 원
  geom_point(data=cap_wide, aes(x=lon,y=lat,size=I(radius*115)),
             shape=21, fill=NA, color="white", stroke=0.8, alpha=0.6) +
  
  # Province 라벨
  geom_label(
    data=cap_wide,
    aes(x=lon, y=lat-radius-0.06, label=name),
    size=3.0, label.size=0, fill="white",
    color="#1A202C", fontface="bold", alpha=0.85,
    label.padding=unit(0.12,"lines")
  ) +
  
  annotate("rect", xmin=128.5, xmax=130.3, ymin=33.0, ymax=34.55,
           fill="white", color="grey65", alpha=0.9, linewidth=0.4) +
  annotate("text", x=129.4, y=34.40, label="Circle size",
           size=3.2, fontface="bold", color="#1A202C", hjust=0.5) +
  geom_point(data=ref_df, aes(x=lon, y=lat, size=I(r*50)),
             shape=21, fill="grey78", color="grey50", stroke=0.5, alpha=0.8) +
  geom_text(data=ref_df, aes(x=lon+0.38, y=lat, label=label),
            size=2.8, color="#1A202C", hjust=0) +
  
  # Transmission 더미 선 (범례용)
  geom_segment(
    data=tibble(
      x=125,xend=125,y=33,yend=33,
      cap_label=factor(c("≥4 GW","3 GW","2 GW","1 GW","<1 GW"),
                       levels=c("≥4 GW","3 GW","2 GW","1 GW","<1 GW")),
      lw=c(3.0,2.2,1.4,0.7,0.35)
    ),
    aes(x=x,y=y,xend=xend,yend=yend,linewidth=I(lw),linetype=cap_label),
    color="#2D3748"
  ) +
  scale_linetype_manual(
    values=rep("solid",5), name="Transmission\ncapacity",
    guide=guide_legend(order=1,
                       override.aes=list(linewidth=c(3.0,2.2,1.4,0.7,0.35),color="#2D3748"))
  ) +
  guides(fill=guide_legend(order=2,title="Technology")) +
  
  coord_sf(xlim=c(126.1, 130.6), ylim=c(33.0, 38.7)) +
  labs(
    title    = "Installed Capacity by Province — 2035",
    subtitle = "NZK Provincial Power Sector Model  |  Circle area ∝ total capacity (GW)",
    caption  = "Source: MacroEnergy optimization results"
  ) +
  theme_void(base_size=12) +
  theme(
    plot.title       = element_text(face="bold",size=15,margin=margin(b=3)),
    plot.subtitle    = element_text(color="grey45",size=10,margin=margin(b=6)),
    plot.caption     = element_text(color="grey55",size=8),
    legend.position  = "right",
    legend.justification = "top",
    legend.title     = element_text(size=11, face="bold"),
    legend.text      = element_text(size=10),
    legend.spacing.y = unit(8, "pt"),
    legend.key.height = unit(16, "pt"),
    legend.box.margin = margin(0, 0, 0, 8),
    plot.margin      = margin(12, 12, 12, 12),
    plot.background  = element_rect(fill="#D6E4F0",color=NA),
    panel.background = element_rect(fill="#D6E4F0",color=NA)
  )

ggsave("capacity_map_2035.png", p, width=11, height=12, dpi=200)
cat("저장 완료: capacity_map_2035.png\n")


###############

library(tidyverse)
library(sf)
library(rnaturalearth)
library(rnaturalearthdata)
library(cowplot)

# ── 1. 색상 & 기술 순서 ───────────────────────────────────────────────
tech_colors <- c(
  "Coal"          = "#1C1C1C",
  "Natural Gas"   = "#2B6CB0",
  "Nuclear"       = "#DD6B20",
  "CHP"           = "#A0AEC0",
  "Solar"         = "#ECC94B",
  "Onshore Wind"  = "#2B9CC7",
  "Offshore Wind" = "#38A169",
  "Battery"       = "#805AD5"
)
tech_order <- c("Coal","Natural Gas","Nuclear","CHP","Solar","Onshore Wind","Offshore Wind","Battery")

# ── 2. Province 좌표 ──────────────────────────────────────────────────
province_coords <- tribble(
  ~province, ~lon,    ~lat,
  "SEL",     126.978, 37.566,
  "INC",     126.505, 37.456,
  "GGI",     127.300, 37.550,
  "GWN",     128.200, 37.750,
  "DJJ",     127.385, 36.350,
  "SJG",     127.100, 36.600,
  "CNA",     126.600, 36.600,
  "CNB",     127.800, 36.700,
  "JNB",     127.100, 35.700,
  "JNA",     126.700, 34.900,
  "KWJ",     126.852, 35.160,
  "GNB",     128.800, 36.400,
  "TAE",     128.601, 35.870,
  "GNA",     128.300, 35.200,
  "USN",     129.312, 35.540,
  "PUS",     129.075, 35.100,
  "JEJ",     126.530, 33.490
)
name_map <- c(SEL="Seoul",INC="Incheon",GGI="Gyeonggi",GWN="Gangwon",
              DJJ="Daejeon",SJG="Sejong",CNA="Chungnam",CNB="Chungbuk",
              JNB="Jeonbuk",JNA="Jeonnam",KWJ="Gwangju",GNB="Gyeongbuk",
              TAE="Daegu",GNA="Gyeongnam",USN="Ulsan",PUS="Busan",JEJ="Jeju")

# ── 3. Capacity 전처리 ────────────────────────────────────────────────
cap_raw  <- read_csv("capacity.csv")
regions  <- province_coords$province

get_province <- function(rid) {
  for (r in regions) if (str_detect(rid, paste0("(?<![A-Z])", r, "(?![A-Z])"))) return(r)
  NA_character_
}

cap <- cap_raw %>%
  filter(variable == "capacity",
         resource_type != "OneWayTransmissionLink{Electricity}") %>%
  mutate(
    province = map_chr(resource_id, get_province),
    tech = case_when(
      str_detect(resource_id, "utility_pv")       ~ "Solar",
      str_detect(resource_id, "onshore_wind")     ~ "Onshore Wind",
      str_detect(resource_id, "offshore_wind")    ~ "Offshore Wind",
      resource_type == "ThermalPower{Coal}"       ~ "Coal",
      resource_type == "ThermalPower{NaturalGas}" ~ "Natural Gas",
      resource_type == "ThermalPower{Uranium}"    ~ "Nuclear",
      str_detect(resource_type, "Steam")          ~ "CHP",
      resource_type == "Battery"                  ~ "Battery",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(province), !is.na(tech), value > 0) %>%
  group_by(province, tech) %>%
  summarise(cap_GW = sum(value)/1000, .groups="drop")

cap_wide <- cap %>%
  pivot_wider(names_from=tech, values_from=cap_GW, values_fill=0) %>%
  left_join(province_coords, by="province") %>%
  mutate(
    total_GW = rowSums(select(., any_of(tech_order)), na.rm=TRUE),
    radius   = scales::rescale(sqrt(total_GW), to=c(0.12, 0.42)),
    name     = name_map[province]
  )
for (tech in tech_order) if (!tech %in% colnames(cap_wide)) cap_wide[[tech]] <- 0
cap_wide <- cap_wide %>% arrange(desc(total_GW))

# ── 4. 파이 폴리곤 ────────────────────────────────────────────────────
make_pie_polygons <- function(df) {
  techs <- tech_order[tech_order %in% names(df %>% select(any_of(tech_order)))]
  result <- list()
  for (i in seq_len(nrow(df))) {
    row   <- df[i,]; cx <- row$lon; cy <- row$lat; r <- row$radius
    vals  <- as.numeric(row[techs]); total <- sum(vals)
    if (total == 0) next
    props  <- vals/total
    angles <- c(0, cumsum(props * 2 * pi))
    for (j in seq_along(techs)) {
      if (props[j] < 1e-6) next
      theta <- seq(angles[j], angles[j+1], length.out=30)
      result[[length(result)+1]] <- tibble(
        x=c(cx, cx+r*sin(theta), cx), y=c(cy, cy+r*cos(theta), cy),
        tech=techs[j], province=row$province,
        group=paste0(row$province,"_",j)
      )
    }
  }
  bind_rows(result)
}
pie_polys <- make_pie_polygons(cap_wide)

# ── 5. Transmission ───────────────────────────────────────────────────
trans <- tibble(
  from = c("SEL","SEL","INC","GGI","GGI","GGI","GWN","CNB","CNB","CNB",
           "CNA","CNA","SJG","SJG","SJG","GNB","GNB","GNB","TAE","USN",
           "USN","GNA","JNB","JNB","JNA","JNA","JNA"),
  to   = c("INC","GGI","GGI","GWN","CNB","CNA","GNB","GNB","JNB","DJJ",
           "DJJ","JNB","CNB","CNA","DJJ","TAE","USN","GNA","GNA","GNA",
           "PUS","PUS","JNA","GNA","KWJ","GNA","JEJ"),
  cap_MW = c(3000,5000,2000,2500,3000,3000,2000,2500,2000,2000,
             2000,1500,1000,1000,800,3000,2500,3000,2500,2000,
             3000,4000,2000,1500,1500,1000,400)
) %>%
  left_join(province_coords %>% rename(lon_from=lon,lat_from=lat), by=c("from"="province")) %>%
  left_join(province_coords %>% rename(lon_to=lon,lat_to=lat),     by=c("to"="province")) %>%
  mutate(lw=case_when(cap_MW>=4000~3.0,cap_MW>=3000~2.2,cap_MW>=2000~1.4,cap_MW>=1000~0.7,TRUE~0.35))

# ── 6. 지도 ───────────────────────────────────────────────────────────
korea <- ne_states(country="South Korea", returnclass="sf")

# ── 7. 지도 플롯 (범례 없음) ──────────────────────────────────────────
p_map <- ggplot() +
  geom_sf(data=korea, fill="#EAEDE8", color="white", linewidth=0.6) +
  geom_segment(data=trans,
               aes(x=lon_from,y=lat_from,xend=lon_to,yend=lat_to,linewidth=I(lw)),
               color="#2D3748", alpha=0.55, lineend="round") +
  geom_polygon(data=pie_polys,
               aes(x=x, y=y, group=group, fill=tech),
               color="white", linewidth=0.2, alpha=0.93) +
  scale_fill_manual(values=tech_colors) +
  geom_point(data=cap_wide, aes(x=lon,y=lat,size=I(radius*115)),
             shape=21, fill=NA, color="white", stroke=0.8, alpha=0.6) +
  geom_label(data=cap_wide,
             aes(x=lon, y=lat-radius-0.05, label=name),
             size=3.0, label.size=0, fill="white",
             color="#1A202C", fontface="bold", alpha=0.85,
             label.padding=unit(0.1,"lines")) +
  coord_sf(xlim=c(126.0, 130.1), ylim=c(33.0, 38.7)) +
  theme_void() +
  theme(
    legend.position  = "none",
    plot.background  = element_rect(fill="#D6E4F0", color=NA),
    panel.background = element_rect(fill="#D6E4F0", color=NA),
    plot.margin      = margin(8,4,8,8)
  )

# ── 8. 범례 플롯 ──────────────────────────────────────────────────────
# 8a. Transmission 범례
trans_leg_df <- tibble(
  x=1, xend=2, y=5:1,
  cap_label = factor(c("≥4 GW","3 GW","2 GW","1 GW","<1 GW"),
                     levels=c("≥4 GW","3 GW","2 GW","1 GW","<1 GW")),
  lw = c(3.0, 2.2, 1.4, 0.7, 0.35)
)

p_trans_leg <- ggplot(trans_leg_df) +
  geom_segment(aes(x=x,y=y,xend=xend,yend=y,linewidth=I(lw)),
               color="#2D3748", lineend="round") +
  geom_text(aes(x=xend+0.15, y=y, label=cap_label),
            hjust=0, size=4.0, color="#1A202C") +
  annotate("text", x=1, y=5.8, label="Transmission capacity",
           hjust=0, size=4.2, fontface="bold", color="#1A202C") +
  xlim(0.8, 4.5) + ylim(0.3, 6.2) +
  theme_void() +
  theme(plot.margin=margin(4,4,4,4))

# 8b. Technology 범례
tech_in_data <- tech_order[tech_order %in% unique(pie_polys$tech)]
tech_leg_df  <- tibble(
  tech  = factor(tech_in_data, levels=tech_in_data),
  y     = rev(seq_along(tech_in_data)),
  color = tech_colors[tech_in_data]
)
p_tech_leg <- ggplot(tech_leg_df) +
  geom_point(aes(x=1, y=y, color=I(color)), size=5, shape=15) +
  geom_text(aes(x=1.4, y=y, label=tech),
            hjust=0, size=4.0, color="#1A202C") +
  annotate("text", x=1, y=max(tech_leg_df$y)+0.8, label="Technology",
           hjust=0, size=4.2, fontface="bold", color="#1A202C") +
  xlim(0.7, 5.5) + ylim(0, max(tech_leg_df$y)+1.2) +
  theme_void() +
  theme(plot.margin=margin(4,4,4,4))

# 8c. Circle size 범례
sqrt_min <- sqrt(min(cap_wide$total_GW))
sqrt_max <- sqrt(max(cap_wide$total_GW))
ref_gw   <- c(5, 15, 30)
ref_r    <- scales::rescale(sqrt(ref_gw), from=c(sqrt_min,sqrt_max), to=c(0.12,0.42))
ref_size <- ref_r * 60  # point size

ref_df <- tibble(x=2, y=c(1.0, 2.2, 3.8),
                 sz=ref_size, label=paste0(ref_gw," GW"))

p_size_leg <- ggplot(ref_df) +
  geom_point(aes(x=x, y=y, size=I(sz)),
             shape=21, fill="grey78", color="grey50", stroke=0.5, alpha=0.8) +
  geom_text(aes(x=x+0.5, y=y, label=label),
            hjust=0, size=4.0, color="#1A202C") +
  annotate("text", x=1.5, y=4.8, label="Circle size (GW)",
           hjust=0, size=4.2, fontface="bold", color="#1A202C") +
  xlim(1, 5) + ylim(0, 5.5) +
  theme_void() +
  theme(plot.margin=margin(4,4,4,4))

# ── 9. 범례 합치기 ────────────────────────────────────────────────────
p_legend <- plot_grid(
  p_trans_leg, p_tech_leg, p_size_leg,
  ncol=1, rel_heights=c(1.2, 1.5, 1.0),
  align="v"
)

# ── 10. 지도 + 범례 합치기 ────────────────────────────────────────────
p_final <- plot_grid(
  p_map, p_legend,
  ncol=2, rel_widths=c(3, 1)
)

# 타이틀 추가
title <- ggdraw() +
  draw_label("Installed Capacity by Province — 2035",
             fontface="bold", size=15, x=0.03, hjust=0) +
  draw_label("NZK Provincial Power Sector Model  |  Circle area ∝ total capacity (GW)",
             size=9.5, color="grey45", x=0.03, y=0.25, hjust=0)

p_out <- plot_grid(title, p_final, ncol=1, rel_heights=c(0.06, 1))

ggsave("capacity_map_2035.png", p_out, width=13, height=12, dpi=200,
       bg="#D6E4F0")
cat("저장 완료: capacity_map_2035.png\n")


##############################################################################

library(tidyverse)

# ── 1. 설정 ───────────────────────────────────────────────────────────
# results 폴더 경로 설정 (본인 경로로 수정)
results_path <- "/Users/hanwoongkim/Desktop/1. Net-Zero_Korea/Bucket/ExampleSystems_NZK_power provincial/results_015"

year_map <- c(
  "results_period_1" = "2021",
  "results_period_2" = "2025",
  "results_period_3" = "2030",
  "results_period_4" = "2035"
)

# ── 2. 색상 & 기술 순서 ───────────────────────────────────────────────
tech_colors <- c(
  "Coal"          = "#1C1C1C",
  "Natural Gas"   = "#2B6CB0",
  "Nuclear"       = "#DD6B20",
  "CHP"           = "#A0AEC0",
  "Solar"         = "#ECC94B",
  "Onshore Wind"  = "#2B9CC7",
  "Offshore Wind" = "#38A169",
  "Battery"       = "#805AD5"
)
tech_order <- c("Coal","Natural Gas","Nuclear","CHP","Solar","Onshore Wind","Offshore Wind","Battery")

# ── 3. Province 정보 ──────────────────────────────────────────────────
regions <- c("SEL","PUS","TAE","INC","KWJ","USN","SJG","GGI",
             "GWN","CNA","CNB","DJJ","JNB","JNA","GNB","GNA","JEJ")
name_map <- c(SEL="Seoul",INC="Incheon",GGI="Gyeonggi",GWN="Gangwon",
              DJJ="Daejeon",SJG="Sejong",CNA="Chungnam",CNB="Chungbuk",
              JNB="Jeonbuk",JNA="Jeonnam",KWJ="Gwangju",GNB="Gyeongbuk",
              TAE="Daegu",GNA="Gyeongnam",USN="Ulsan",PUS="Busan",JEJ="Jeju")

get_province <- function(rid) {
  for (r in regions) {
    if (str_detect(rid, paste0("(?<![A-Z])", r, "(?![A-Z])"))) return(r)
  }
  NA_character_
}

# ── 4. 4개 period 읽어서 합치기 ──────────────────────────────────────
cap_all <- map_dfr(names(year_map), function(period) {
  path <- file.path(results_path, period, "capacity.csv")
  if (!file.exists(path)) {
    warning(paste("파일 없음:", path))
    return(NULL)
  }
  read_csv(path, show_col_types = FALSE) %>%
    mutate(year = year_map[[period]])
})

cat("전체 행 수:", nrow(cap_all), "\n")
cat("연도 확인:", unique(cap_all$year), "\n")

# ── 5. 전처리 ─────────────────────────────────────────────────────────
cap <- cap_all %>%
  filter(
    variable == "capacity",
    resource_type != "OneWayTransmissionLink{Electricity}"
  ) %>%
  mutate(
    province = map_chr(resource_id, get_province),
    tech = case_when(
      str_detect(resource_id, "utility_pv")       ~ "Solar",
      str_detect(resource_id, "onshore_wind")     ~ "Onshore Wind",
      str_detect(resource_id, "offshore_wind")    ~ "Offshore Wind",
      resource_type == "ThermalPower{Coal}"       ~ "Coal",
      resource_type == "ThermalPower{NaturalGas}" ~ "Natural Gas",
      resource_type == "ThermalPower{Uranium}"    ~ "Nuclear",
      str_detect(resource_type, "Steam")          ~ "CHP",
      resource_type == "Battery"                  ~ "Battery",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(province), !is.na(tech), value > 0) %>%
  group_by(province, tech, year) %>%
  summarise(cap_GW = sum(value) / 1000, .groups = "drop") %>%
  mutate(
    tech     = factor(tech, levels = tech_order),
    year     = factor(year, levels = c("2021","2025","2030","2035")),
    province = factor(province, levels = regions),
    name     = name_map[as.character(province)]
  )

# ── 6. 플롯 ───────────────────────────────────────────────────────────
# 17개 province × 4년 stacked bar, facet_wrap으로 5열 배치
p <- ggplot(cap, aes(x = year, y = cap_GW, fill = tech)) +
  geom_col(width = 0.75, color = "white", linewidth = 0.2) +
  scale_fill_manual(
    values = tech_colors,
    name   = "Technology",
    breaks = tech_order,
    guide  = guide_legend(
      nrow          = 1,
      title.position = "top"
    )
  ) +
  facet_wrap(
    ~ name,
    ncol   = 5,
    scales = "free_y"   # province마다 y축 자동 조정
  ) +
  scale_y_continuous(
    labels = scales::label_number(suffix = " GW", accuracy = 1),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title    = "Installed Capacity by Province & Year",
    subtitle = "NZK Provincial Power Sector Model  |  2021 → 2025 → 2030 → 2035",
    caption  = "Source: MacroEnergy optimization results",
    x        = NULL,
    y        = "Capacity (GW)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    # 패널
    strip.text       = element_text(face = "bold", size = 10.5),
    strip.background = element_rect(fill = "#F0F4F0", color = NA),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.spacing      = unit(0.8, "lines"),
    # 축
    axis.text.x  = element_text(size = 8.5, angle = 30, hjust = 1),
    axis.text.y  = element_text(size = 8),
    axis.title.y = element_text(size = 9, color = "grey50"),
    # 범례
    legend.position  = "bottom",
    legend.title     = element_text(size = 9, face = "bold"),
    legend.text      = element_text(size = 9),
    legend.key.size  = unit(10, "pt"),
    legend.spacing.x = unit(6, "pt"),
    # 제목
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "grey50", size = 9, margin = margin(b = 8)),
    plot.caption  = element_text(color = "grey60", size = 7.5),
    plot.margin   = margin(12, 12, 12, 12),
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave("capacity_by_province_year.png", p,
       width = 16, height = 14, dpi = 200)
cat("저장 완료: capacity_by_province_year.png\n")

# ── 7. 숫자 요약 (확인용) ─────────────────────────────────────────────
cat("\n=== 전국 합계 (GW) ===\n")
cap %>%
  group_by(year, tech) %>%
  summarise(total = sum(cap_GW), .groups = "drop") %>%
  pivot_wider(names_from = year, values_from = total, values_fill = 0) %>%
  print()

##############################################################################









library(tidyverse)
library(ggplot2)
library(cowplot)

# ============================================================
# 설정
# ============================================================
BASE_PATH <- "/Users/hanwoongkim/Desktop/1. Net-Zero_Korea/Bucket/ExampleSystems_NZK_power provincial"
RESULTS   <- "results_022"
PERIOD    <- "results_period_1"

flows_path   <- file.path(BASE_PATH, RESULTS, PERIOD, "flows.csv")
weights_path <- file.path(BASE_PATH, RESULTS, PERIOD, "time_weights.csv")

tech_colors <- c(
  "Coal"          = "#1C1C1C",
  "Natural Gas"   = "#2B6CB0",
  "Nuclear"       = "#DD6B20",
  "CHP"           = "#A0AEC0",
  "Solar"         = "#ECC94B",
  "Onshore Wind"  = "#2B9CC7",
  "Offshore Wind" = "#38A169"
)

prov_names <- c(
  SEL="Seoul", PUS="Busan", TAE="Daegu", INC="Incheon",
  KWJ="Gwangju", USN="Ulsan", SJG="Sejong", GGI="Gyeonggi",
  GWN="Gangwon", CNA="Chungnam", CNB="Chungbuk", DJJ="Daejeon",
  JNB="Jeonbuk", JNA="Jeonnam", GNB="Gyeongbuk", GNA="Gyeongnam", JEJ="Jeju"
)

# ============================================================
# 데이터 로드
# ============================================================
flows <- read_csv(flows_path, show_col_types = FALSE)

# ============================================================
# 기술 분류
# ============================================================
classify_tech <- function(rt, rid) {
  case_when(
    str_detect(rt, "ThermalSteam") ~ "CHP",
    str_detect(rt, "Coal")        ~ "Coal",
    str_detect(rt, "NaturalGas")  ~ "Natural Gas",
    str_detect(rt, "Uranium")     ~ "Nuclear",
    str_detect(rid, "pv|solar")   ~ "Solar",
    str_detect(rid, "onshore|onwind") ~ "Onshore Wind",
    str_detect(rid, "offshore|offwind") ~ "Offshore Wind",
    str_detect(rt, "VRE") & str_detect(rid, "wind") ~ "Onshore Wind",
    str_detect(rt, "VRE")         ~ "Solar",
    TRUE ~ NA_character_
  )
}

# ============================================================
# generation flow 추출
# ============================================================
gen <- flows %>%
  filter(commodity == "Electricity", variable == "flow") %>%
  filter(str_detect(node_out, "^elec_")) %>%
  filter(!str_detect(node_in, "^elec_")) %>%
  mutate(
    province = str_extract(node_out, "(?<=elec_)[A-Z]+"),
    tech = classify_tech(resource_type, resource_id)
  ) %>%
  filter(!is.na(tech), value > 0.01) %>%
  select(province, tech, time, value)

# ============================================================
# 수요 추출
# ============================================================
demand <- flows %>%
  filter(commodity == "Electricity", variable == "flow") %>%
  filter(str_detect(node_in, "^elec_")) %>%
  filter(!str_detect(node_out, "^elec_")) %>%
  mutate(province = str_extract(node_in, "(?<=elec_)[A-Z]+")) %>%
  group_by(province, time) %>%
  summarise(demand_MW = sum(value, na.rm = TRUE), .groups = "drop")

# ============================================================
# peak day & top 2 provinces 선택
# ============================================================
total_demand_by_time <- demand %>%
  group_by(time) %>%
  summarise(total = sum(demand_MW))

peak_time  <- total_demand_by_time %>% slice_max(total, n=1) %>% pull(time)
peak_day   <- ceiling(peak_time / 24)
hour_start <- (peak_day - 1) * 24 + 1
hour_end   <- peak_day * 24
cat("Peak day:", peak_day, "| Hours:", hour_start, "~", hour_end, "\n")

top2 <- demand %>%
  group_by(province) %>%
  summarise(mean_d = mean(demand_MW)) %>%
  slice_max(mean_d, n = 2) %>%
  pull(province)
cat("Top 2 provinces:", paste(top2, collapse=", "), "\n")

# ============================================================
# 필터 & 정렬 (시간 순서 보장)
# ============================================================
gen_day <- gen %>%
  filter(province %in% top2, time >= hour_start, time <= hour_end) %>%
  mutate(hour = time - hour_start + 1,
         tech = factor(tech, levels = names(tech_colors))) %>%
  arrange(province, tech, hour)

demand_day <- demand %>%
  filter(province %in% top2, time >= hour_start, time <= hour_end) %>%
  mutate(hour = time - hour_start + 1) %>%
  arrange(province, hour)

# ============================================================
# 플롯 함수
# ============================================================
make_plot <- function(prov) {
  g <- gen_day %>% filter(province == prov)
  d <- demand_day %>% filter(province == prov)
  
  used <- unique(as.character(g$tech))
  cols <- tech_colors[names(tech_colors) %in% used]
  
  ggplot() +
    geom_area(data = g,
              aes(x = hour, y = value/1000, fill = tech),
              position = "stack", alpha = 0.88) +
    geom_line(data = d,
              aes(x = hour, y = demand_MW/1000),
              color = "#E53E3E", linewidth = 1.0,
              linetype = "dashed") +
    scale_fill_manual(values = cols, name = "Technology") +
    scale_x_continuous(breaks = c(1,6,12,18,24),
                       labels = c("00:00","06:00","12:00","18:00","24:00")) +
    scale_y_continuous(labels = scales::comma_format(suffix=" GW")) +
    labs(title = prov_names[prov], x = "Hour of Day", y = "Generation (GW)") +
    theme_minimal(base_size = 12) +
    theme(
      plot.title      = element_text(face="bold", size=14),
      legend.position = "none",
      panel.grid.minor = element_blank(),
      axis.text.x = element_text(angle=30, hjust=1)
    )
}

p1 <- make_plot(top2[1])
p2 <- make_plot(top2[2])

# legend
leg_plot <- ggplot(gen_day, aes(x=hour, y=value, fill=tech)) +
  geom_area() +
  scale_fill_manual(values=tech_colors, name="Technology") +
  theme(legend.position="right",
        legend.key.size=unit(0.8,"cm"),
        legend.text=element_text(size=11))
leg <- get_legend(leg_plot)

# 제목
title <- ggdraw() +
  draw_label(
    paste0("Hourly Dispatch — Peak Representative Day (Day ", peak_day, ")"),
    fontface="bold", size=15, x=0.03, hjust=0
  ) +
  draw_label(
    "NZK Provincial Power Sector Model  |  2021 Baseline  |  Red dashed = demand",
    size=10, color="gray40", x=0.03, hjust=0, y=0.25
  )

final <- plot_grid(
  title,
  plot_grid(
    plot_grid(p1, p2, nrow=1, labels=c("A","B"), label_size=13),
    leg,
    rel_widths=c(1, 0.15)
  ),
  nrow=2, rel_heights=c(0.12, 1)
)

out <- file.path(BASE_PATH, RESULTS, "dispatch_peak_day.png")
ggsave(out, final, width=14, height=6, dpi=150)
cat("✅ Saved:", out, "\n")