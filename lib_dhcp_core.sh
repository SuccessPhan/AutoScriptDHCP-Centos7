#!/bin/bash
# ==========================================
# FILE: lib_dhcp_core.sh (Bản Final - Tương thích 100% CentOS 7 Bash 4.2)
# ==========================================

# 1. KIỂM TRA ĐỊNH DẠNG IP (IPv4)
is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a oct=($ip)
        [[ ${oct[0]} -le 255 && ${oct[1]} -le 255 && ${oct[2]} -le 255 && ${oct[3]} -le 255 ]]
        return $?
    fi
    return 1
}

# 2. KIỂM TRA LỚP MẠNG HỢP LỆ (IPv4 Class Firewall)
is_valid_ipv4_class() {
    local ip=$1
    local octet1=$(echo "$ip" | cut -d'.' -f1)
    if [ "$octet1" -ge 224 ] || [ "$octet1" -eq 127 ] || [ "$octet1" -eq 0 ]; then return 1; fi
    if echo "$ip" | grep -q "^169\.254\."; then return 1; fi
    return 0
}

# 3. KIỂM TRA ĐỊNH DẠNG TÊN MIỀN (Domain Name)
is_valid_domain() {
    local domain=$1
    if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then return 0; fi
    return 1
}

# 4. KIỂM TRA ĐỊNH DẠNG HOSTNAME
is_valid_hostname() {
    local host=$1
    if [[ "$host" =~ ^[a-zA-Z0-9_-]+$ ]]; then return 0; fi
    return 1
}

# 5. XỬ LÝ TOÁN HỌC MẠNG
get_valid_network_logic() {
    while true; do
        read -p "Nhập Subnet (VD: 192.168.1.0): " subnet
        if ! is_valid_ip "$subnet"; then echo "-> [LỖI] Định dạng Subnet không hợp lệ!"; continue; fi
        if ! is_valid_ipv4_class "$subnet"; then echo "-> [LỖI NGHIÊM TRỌNG] Subnet thuộc lớp mạng cấm (Class D/E, Loopback hoặc APIPA)!"; continue; fi
        
        read -p "Nhập Netmask (VD: 255.255.255.0): " netmask
        if ! is_valid_ip "$netmask"; then echo "-> [LỖI] Định dạng Netmask không hợp lệ!"; continue; fi

        calculated_network=$(ipcalc -n "$subnet" "$netmask" 2>/dev/null | cut -d= -f2)
        if [ -z "$calculated_network" ]; then echo "-> [LỖI] Cặp Subnet và Netmask này không hợp lệ về mặt định tuyến!"; continue; fi
        if [ "$subnet" != "$calculated_network" ]; then echo "-> [LỖI LOGIC] Với Netmask $netmask, địa chỉ mạng chuẩn phải là '$calculated_network'!"; continue; fi
        break
    done
}

# 6. ÉP NHẬP DOMAIN HỢP LỆ (Tương thích Bash 4.2)
get_valid_domain() {
    local prompt=$1; local var_name=$2
    while true; do
        read -p "$prompt" temp_domain
        if is_valid_domain "$temp_domain"; then 
            printf -v "$var_name" "%s" "$temp_domain"
            break
        else 
            echo "-> [LỖI] Domain sai định dạng (VD chuẩn: sgu.edu.vn, không chứa khoảng trắng/ký tự đặc biệt)!"
        fi
    done
}

# 7. ÉP NHẬP HOSTNAME HỢP LỆ (Tương thích Bash 4.2)
get_valid_hostname() {
    local prompt=$1; local var_name=$2
    while true; do
        read -p "$prompt" temp_host
        if is_valid_hostname "$temp_host"; then 
            printf -v "$var_name" "%s" "$temp_host"
            break
        else 
            echo "-> [LỖI] Tên Host sai định dạng (Chỉ dùng chữ, số, dấu - hoặc _, không có khoảng trắng)!"
        fi
    done
}

# 8. XỬ LÝ SỐ NGUYÊN & LOGIC THỜI GIAN THUÊ (Tương thích Bash 4.2)
get_valid_lease_times() {
    local var_def=$1; local var_max=$2
    while true; do
        read -p "Nhập Default Lease Time (giây): " temp_def
        if ! [[ "$temp_def" =~ ^[0-9]+$ ]]; then echo "-> [LỖI] Chỉ chấp nhận giá trị số nguyên!"; continue; fi
        
        read -p "Nhập Max Lease Time (giây): " temp_max
        if ! [[ "$temp_max" =~ ^[0-9]+$ ]]; then echo "-> [LỖI] Chỉ chấp nhận giá trị số nguyên!"; continue; fi
        
        if [ "$temp_def" -gt "$temp_max" ]; then
            echo "-> [LỖI LOGIC] Max Lease Time ($temp_max) không được nhỏ hơn Default Lease Time ($temp_def)!"
            continue
        fi
        
        printf -v "$var_def" "%s" "$temp_def"
        printf -v "$var_max" "%s" "$temp_max"
        break
    done
}

# 9. CÁC HÀM XỬ LÝ IP VÀ CONFLICT (Tương thích Bash 4.2)
ip_to_int() {
    local ip=$1; local a b c d
    IFS=. read a b c d <<< "$ip"
    echo $(((a<<24) + (b<<16) + (c<<8) + d))
}

check_router_conflict() {
    local router=$1; local start=$2; local end=$3
    local r_int=$(ip_to_int "$router")
    local s_int=$(ip_to_int "$start")
    local e_int=$(ip_to_int "$end")
    if [ $r_int -ge $s_int ] && [ $r_int -le $e_int ]; then return 1; fi
    return 0
}

check_scope_exists() {
    local check_sub=$1
    grep -q "^subnet $check_sub " "/etc/dhcp/dhcpd.conf"
    return $?
}

get_ip_in_subnet() {
    local prompt=$1; local var_name=$2; local sub=$3; local mask=$4
    local net_int=$(ip_to_int "$sub")
    local bcast=$(ipcalc -b "$sub" "$mask" 2>/dev/null | cut -d= -f2)
    local bcast_int=$(ip_to_int "$bcast")
    while true; do
        read -p "$prompt" temp_ip
        if ! is_valid_ip "$temp_ip"; then echo "-> [LỖI] Định dạng địa chỉ IP sai!"; continue; fi
        local temp_int=$(ip_to_int "$temp_ip")
        if [ $temp_int -le $net_int ] || [ $temp_int -ge $bcast_int ]; then
            echo "-> [LỖI] IP phải lớn hơn Mạng gốc ($sub) và nhỏ hơn Broadcast ($bcast)!"
            continue
        fi
        printf -v "$var_name" "%s" "$temp_ip"
        break
    done
}

get_non_empty_string() {
    local prompt=$1; local var_name=$2
    while true; do
        read -p "$prompt" temp_str
        if [ -n "$temp_str" ]; then 
            printf -v "$var_name" "%s" "$temp_str"
            break
        else 
            echo "-> [LỖI] Trường dữ liệu không được để trống!"
        fi
    done
}

get_valid_number() {
    local prompt=$1; local var_name=$2
    while true; do
        read -p "$prompt" temp_num
        if [[ "$temp_num" =~ ^[0-9]+$ ]]; then 
            printf -v "$var_name" "%s" "$temp_num"
            break
        else 
            echo "-> [LỖI] Chỉ chấp nhận giá trị số nguyên!"
        fi
    done
}
