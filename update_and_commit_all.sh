#!/bin/bash
set -euo pipefail

download_with_fallback () {
    local output_file="$1"
    local url="$2"
    local wget_log="${output_file}.wget.log"
    local curl_log="${output_file}.curl.log"
    local wget_exit_code=0
    local curl_exit_code=0
    local max_attempts=4
    local attempt=1
    local backoff=2

    while [ "$attempt" -le "$max_attempts" ]; do
        echo "Download attempt ${attempt}/${max_attempts}: ${url}"
        if wget -q --tries=8 --waitretry=2 --timeout=30 --read-timeout=60 -O "${output_file}" "${url}" 2>"${wget_log}"; then
            echo "wget download succeeded"
            rm -f "${wget_log}" "${curl_log}"
            return 0
        else
            wget_exit_code=$?
        fi

        echo "wget failed with exit code ${wget_exit_code}. Falling back to curl."
        echo "wget stderr:"
        cat "${wget_log}" || true

        if curl -fL --retry 8 --retry-delay 2 --retry-all-errors --connect-timeout 30 --max-time 120 -o "${output_file}" "${url}" 2>"${curl_log}"; then
            echo "curl fallback succeeded"
            rm -f "${wget_log}" "${curl_log}"
            return 0
        else
            curl_exit_code=$?
        fi

        echo "curl fallback failed with exit code ${curl_exit_code}"
        echo "curl stderr:"
        cat "${curl_log}" || true

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo "Retrying full download flow after ${backoff}s backoff..."
            sleep "$backoff"
            backoff=$((backoff * 2))
        fi
        attempt=$((attempt + 1))
    done

    return "${curl_exit_code}"
}

validate_zip () {
    local zip_file="$1"

    if unzip -tq "$zip_file" >/dev/null 2>&1; then
        return 0
    fi

    echo "Downloaded file is not a valid ZIP archive: ${zip_file}" >&2
    return 9
}

fetch_and_sort () {
    # $1 is the table name, $2 is the URL
    local table=$1
    local zip_url=$2
    local zip="$1.csv.zip"
    local csv="$1.csv"
    local csv_unsorted="$1.csv.unsorted"
    local csv_old="$1.csv.old"
    local commit_txt="$1.commit.txt"
    mv "$csv" "$csv_old"
    download_with_fallback "$zip" "$2"
    validate_zip "$zip"
    unzip -q -o "$zip"
    # This should have created the .csv file
    mv "$csv" "$csv_unsorted"
    # Construct new CSV with heading line + sorted other lines
    python sort_csv.py "$csv_unsorted" > "$csv"
    echo "Updated $csv" > "$commit_txt"
#    echo "$(git log --oneline --pretty="@%h"  --stat   |grep -v \| |  tr "\n" " "  |  tr "@" "\n")" >> $commit_txt
}

add_and_commit () {
    local csv="$1.csv"
    local commit_txt="$1.commit.txt"
    git add "$csv"
    git commit -F "$commit_txt" && \
        git push -q origin master \
        || true
}

git config --global user.email "farabot@example.com"
git config --global user.name "Farabot"

fetch_and_sort FARA_All_RegistrantDocs "https://efile.fara.gov/bulk/zip/FARA_All_RegistrantDocs.csv.zip"
add_and_commit FARA_All_RegistrantDocs
