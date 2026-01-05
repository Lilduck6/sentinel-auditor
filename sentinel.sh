#!/bin/bash
# Shebang obligatoire

# ==============================================================================
# NOM : Sentinel - Linux Server Auditor (Ultimate Version)
# DESCRIPTION : Analyse complète (CPU, RAM, Disque, Services, Sécurité) + Alerte Discord
# AUTEUR : [Ton Nom]
# DATE : $(date +%Y-%m-%d)
# ==============================================================================

# --- Variables de Configuration ---
REPORT_FILE="sentinel_report_$(date +%Y%m%d).log"
THRESHOLD_DISK=80   # Alerte si disque > 80%
THRESHOLD_RAM=90    # Alerte si RAM > 90%

# ------------------------------------------------------------------
# CONFIGURATION WEBHOOK (Laisser vide pour désactiver)
# Exemple : "https://discord.com/api/webhooks/..."
# ------------------------------------------------------------------
WEBHOOK_URL="https://discord.com/api/webhooks/1457832062907322430/VOByh7-86F-ZygRac2nBBbyJtfe_HbZNAxNiyIOqDz_k98mmrli7wqCIBMuFEng9BqxH" 

# Codes couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Fonctions Utilitaires ---

# Fonction pour envoyer une alerte Discord
send_discord_alert() {
    local message="$1"
    # On n'envoie que si une URL est configurée
    if [ -n "$WEBHOOK_URL" ]; then
        curl -H "Content-Type: application/json" \
             -X POST \
             -d "{\"content\": \"🚨 **SENTINEL ALERT** : $message\"}" \
             "$WEBHOOK_URL" > /dev/null 2>&1
    fi
}

# Fonction de log et d'affichage
log_msg() {
    local level="$1"
    local message="$2"
    local color="$NC"
    
    case "$level" in
        "INFO") color="$BLUE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ALERT") 
            color="$RED"
            # Si c'est une ALERTE, on notifie sur Discord
            send_discord_alert "$message"
            ;;
    esac

    # Affichage écran
    echo -e "${color}[$level]${NC} $message"
    # Écriture dans le fichier log
    echo "[$level] $(date +'%H:%M:%S') - $message" >> "$REPORT_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_msg "WARNING" "Script non lancé en root. Vérifications limitées."
    fi
}

# --- Fonctions de Monitoring ---

# 1. Audit CPU (Charge système)
check_cpu() {
    log_msg "INFO" "Analyse de la charge CPU..."
    # Récupère le load average sur 1 minute
    cpu_load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
    # Nombre de coeurs
    cpu_cores=$(nproc)
    
    # Comparaison avec awk (gère les décimales)
    is_overload=$(echo "$cpu_load $cpu_cores" | awk '{if ($1 > $2) print 1; else print 0}')
    
    if [ "$is_overload" -eq 1 ]; then
        log_msg "ALERT" "Surcharge CPU critique : Load $cpu_load (pour $cpu_cores coeurs)"
    else
        log_msg "SUCCESS" "Charge CPU normale : $cpu_load"
    fi
}

# 2. Audit RAM
check_ram() {
    log_msg "INFO" "Analyse de la mémoire RAM..."
    ram_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
    
    if [ "$ram_usage" -ge "$THRESHOLD_RAM" ]; then
        log_msg "ALERT" "Utilisation RAM critique : $ram_usage%"
    else
        log_msg "SUCCESS" "Utilisation RAM stable : $ram_usage%"
    fi
}

# 3. Audit Disque
check_disk() {
    log_msg "INFO" "Analyse de l'espace disque..."
    df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $1 }' | while read output; do
        usage_percent=$(echo $output | awk '{ print $1}' | cut -d'%' -f1)
        partition=$(echo $output | awk '{ print $2 }')

        if [ "$usage_percent" -ge "$THRESHOLD_DISK" ]; then
            log_msg "ALERT" "Espace critique sur $partition ($usage_percent%)"
        else
            log_msg "SUCCESS" "Partition $partition OK ($usage_percent%)"
        fi
    done
}

# 4. Vérification des Services
check_services() {
    log_msg "INFO" "Vérification des services essentiels..."
    # Liste des services à surveiller (ajoute les tiens ici : apache2, nginx, mysql...)
    SERVICES=("ssh" "cron" "rsyslog") 
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_msg "SUCCESS" "Service '$service' est ACTIF."
        else
            log_msg "ALERT" "Service '$service' est ÉTEINT ou INTROUVABLE !"
        fi
    done
}

# 5. Audit Sécurité
check_security() {
    log_msg "INFO" "Audit des tentatives de connexion échouées..."
    LOG_AUTH="/var/log/auth.log"
    
    if [ ! -f "$LOG_AUTH" ]; then
        log_msg "WARNING" "Fichier $LOG_AUTH introuvable."
        return
    fi

    failed_attempts=$(grep "Failed password" "$LOG_AUTH" | wc -l)
    
    if [ "$failed_attempts" -gt 0 ]; then
        log_msg "WARNING" "$failed_attempts intrusion(s) potentielle(s) détectée(s) aujourd'hui !"
        grep "Failed password" "$LOG_AUTH" | tail -n 3 | awk '{print "   -> Suspect: " $11 " (" $1, $2, $3 ")"}'
    else
        log_msg "SUCCESS" "Aucune tentative d'intrusion détectée."
    fi
}

usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo "  -f, --full      Audit complet (CPU, RAM, Disque, Services, Sécurité)"
    echo "  -d, --disk      Disque uniquement"
    echo "  -h, --help      Afficher l'aide"
    exit 0
}

# --- Main ---

if [ $# -eq 0 ]; then usage; fi

echo "--- RAPPORT SENTINEL $(date) ---" > "$REPORT_FILE"
check_root

while [ "$1" != "" ]; do
    case $1 in
        -f | --full )
            check_disk
            check_ram
            check_cpu      # Nouveau
            check_services # Nouveau
            check_security
            ;;
        -d | --disk ) check_disk ;;
        -s | --security ) check_security ;;
        -h | --help ) usage ;;
        * ) usage ;;
    esac
    shift
done

echo ""
log_msg "INFO" "Rapport généré : $REPORT_FILE"