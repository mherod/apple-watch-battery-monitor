#include <ctype.h>
#include <libimobiledevice/companion_proxy.h>
#include <libimobiledevice/libimobiledevice.h>
#include <plist/plist.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <libimobiledevice/libimobiledevice.h>

typedef struct {
    char *udid;
    char *name;
    char *product_type;
    char *battery_str;
    char *charging_str;
    int is_watch;
    int has_battery;
} watch_device_info_t;

static const char *idevice_connection_name(enum idevice_connection_type type) {
    return type == CONNECTION_NETWORK ? "network" : "usbmuxd";
}

static const char *companion_proxy_error_name(companion_proxy_error_t err) {
    switch (err) {
        case COMPANION_PROXY_E_SUCCESS:
            return "COMPANION_PROXY_E_SUCCESS";
        case COMPANION_PROXY_E_INVALID_ARG:
            return "COMPANION_PROXY_E_INVALID_ARG";
        case COMPANION_PROXY_E_PLIST_ERROR:
            return "COMPANION_PROXY_E_PLIST_ERROR";
        case COMPANION_PROXY_E_MUX_ERROR:
            return "COMPANION_PROXY_E_MUX_ERROR";
        case COMPANION_PROXY_E_SSL_ERROR:
            return "COMPANION_PROXY_E_SSL_ERROR";
        case COMPANION_PROXY_E_NOT_ENOUGH_DATA:
            return "COMPANION_PROXY_E_NOT_ENOUGH_DATA";
        case COMPANION_PROXY_E_TIMEOUT:
            return "COMPANION_PROXY_E_TIMEOUT";
        case COMPANION_PROXY_E_OP_IN_PROGRESS:
            return "COMPANION_PROXY_E_OP_IN_PROGRESS";
        case COMPANION_PROXY_E_NO_DEVICES:
            return "COMPANION_PROXY_E_NO_DEVICES";
        case COMPANION_PROXY_E_UNSUPPORTED_KEY:
            return "COMPANION_PROXY_E_UNSUPPORTED_KEY";
        case COMPANION_PROXY_E_TIMEOUT_REPLY:
            return "COMPANION_PROXY_E_TIMEOUT_REPLY";
        case COMPANION_PROXY_E_UNKNOWN_ERROR:
            return "COMPANION_PROXY_E_UNKNOWN_ERROR";
        default:
            return "COMPANION_PROXY_E_UNKNOWN";
    }
}

static void print_usage(const char *prog) {
    fprintf(stderr, "Usage: %s [--json] [--watch-only] [iPhone UDID]\n", prog);
    fprintf(stderr, "  --json, -j       Output JSON only\n");
    fprintf(stderr, "  --watch-only, -w Only include Apple Watch entries\n");
    fprintf(stderr, "  --help           Show this message\n");
}

static int start_proxy(idevice_t device, companion_proxy_client_t *proxy) {
    companion_proxy_error_t perr = companion_proxy_client_start_service(device, proxy, "watch-battery");
    if (perr != COMPANION_PROXY_E_SUCCESS) {
        fprintf(stderr, "Error: Cannot start companion_proxy service: %s (%d)\n",
                companion_proxy_error_name(perr), perr);
        return -1;
    }
    return 0;
}

static int contains_watch(const char *value) {
    if (!value) {
        return 0;
    }
    size_t len = strlen(value);
    for (size_t i = 0; i + 5 <= len; i++) {
        if (strncasecmp(value + i, "Watch", 5) == 0) {
            return 1;
        }
    }
    return 0;
}

static char *query_key(idevice_t device, const char *watch_udid, const char *key, int verbose) {
    companion_proxy_client_t proxy = NULL;
    if (start_proxy(device, &proxy) != 0)
        return NULL;

    plist_t value = NULL;
    plist_t selected = NULL;
    companion_proxy_error_t perr = companion_proxy_get_value_from_registry(proxy, watch_udid, key, &value);

    char *result = NULL;
    if (perr == COMPANION_PROXY_E_SUCCESS && value) {
        if (PLIST_IS_DICT(value)) {
            selected = plist_dict_get_item(value, key);
        } else {
            selected = value;
        }

        if (selected) {
            uint8_t bval = 0;
            uint64_t uval = 0;

            switch (plist_get_node_type(selected)) {
                case PLIST_STRING: {
                    char *tmp = NULL;
                    plist_get_string_val(selected, &tmp);
                    if (tmp) {
                        result = strdup(tmp);
                        plist_mem_free(tmp);
                    }
                    break;
                }
                case PLIST_UINT:
                    plist_get_uint_val(selected, &uval);
                    asprintf(&result, "%llu", uval);
                    break;
                case PLIST_BOOLEAN:
                    plist_get_bool_val(selected, &bval);
                    result = strdup(bval ? "true" : "false");
                    break;
                default:
                    break;
            }
        }
    } else if (verbose) {
        fprintf(stderr, "lookup %s on %s failed: %s (%d)\n", key, watch_udid, companion_proxy_error_name(perr), perr);
    }

    if (value)
        plist_free(value);
    if (proxy)
        companion_proxy_client_free(proxy);

    return result;
}

static void free_watch_info(watch_device_info_t *info) {
    if (!info)
        return;
    free(info->udid);
    free(info->name);
    free(info->product_type);
    free(info->battery_str);
    free(info->charging_str);
    free(info);
}

static watch_device_info_t *collect_watch_info(idevice_t device, const char *watch_udid) {
    watch_device_info_t *info = calloc(1, sizeof(*info));
    if (!info)
        return NULL;

    info->udid = strdup(watch_udid);
    if (!info->udid) {
        free_watch_info(info);
        return NULL;
    }

    info->product_type = query_key(device, watch_udid, "ProductType", 0);
    if (!info->product_type) {
        info->product_type = query_key(device, watch_udid, "ProductTypeString", 0);
    }

    info->name = query_key(device, watch_udid, "DeviceName", 0);
    info->battery_str = query_key(device, watch_udid, "BatteryCurrentCapacity", 0);
    if (!info->battery_str) {
        info->battery_str = query_key(device, watch_udid, "CurrentCapacity", 0);
    }
    info->charging_str = query_key(device, watch_udid, "BatteryIsCharging", 0);

    info->is_watch = contains_watch(info->product_type);
    info->has_battery = (info->battery_str != NULL && info->battery_str[0] != '\0');

    return info;
}

static void print_json_escape(FILE *out, const char *value) {
    fputc('"', out);
    if (!value) {
        fputc('"', out);
        return;
    }
    for (const unsigned char *c = (const unsigned char *)value; *c; c++) {
        switch (*c) {
            case '\\':
                fputs("\\\\", out);
                break;
            case '"':
                fputs("\\\"", out);
                break;
            case '\b':
                fputs("\\b", out);
                break;
            case '\f':
                fputs("\\f", out);
                break;
            case '\n':
                fputs("\\n", out);
                break;
            case '\r':
                fputs("\\r", out);
                break;
            case '\t':
                fputs("\\t", out);
                break;
            default:
                if (isprint(*c)) {
                    fputc(*c, out);
                }
                break;
        }
    }
    fputc('"', out);
}

static void print_json_device(FILE *out, const watch_device_info_t *info, int is_last, int watch_only_filter) {
    int charging = info->charging_str && (strcasecmp(info->charging_str, "true") == 0 || strcmp(info->charging_str, "1") == 0);
    uint64_t battery = info->battery_str ? strtoull(info->battery_str, NULL, 10) : 0;

    if (!is_last) {
        fputc(',', out);
    }
    fputc('{', out);

    fputs("\"udid\":", out);
    print_json_escape(out, info->udid);

    fputs(",\"name\":", out);
    print_json_escape(out, info->name ? info->name : "Unknown");

    fputs(",\"productType\":", out);
    print_json_escape(out, info->product_type ? info->product_type : "Unknown");

    fputs(",\"isWatch\":", out);
    fprintf(out, "%s", info->is_watch ? "true" : "false");

    fputs(",\"battery\":", out);
    if (info->has_battery) {
        fprintf(out, "%llu", battery);
    } else {
        fputs("null", out);
    }

    fputs(",\"charging\":", out);
    if (info->charging_str) {
        fprintf(out, "%s", charging ? "true" : "false");
    } else {
        fputs("null", out);
    }

    if (watch_only_filter) {
        fputs(",\"watchOnly\":true", out);
    }

    fputc('}', out);
}

static void print_human_device(const watch_device_info_t *info) {
    if (!info->has_battery) {
        return;
    }

    uint64_t battery = strtoull(info->battery_str, NULL, 10);
    int charging = info->charging_str && (strcasecmp(info->charging_str, "true") == 0 || strcmp(info->charging_str, "1") == 0);

    printf("%s: %s (%s) — %llu%% %s\n",
           info->name ? info->name : "Unknown Watch",
           info->product_type ? info->product_type : "Unknown",
           info->udid,
           battery,
           charging ? "(charging)" : "");
}

int main(int argc, char **argv) {
    const char *iphone_udid = NULL;
    int json_output = 0;
    int watch_only = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0 || strcmp(argv[i], "-j") == 0) {
            json_output = 1;
        } else if (strcmp(argv[i], "--watch-only") == 0 || strcmp(argv[i], "-w") == 0) {
            watch_only = 1;
        } else if (strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strncmp(argv[i], "-", 1) == 0) {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 2;
        } else if (!iphone_udid) {
            iphone_udid = argv[i];
        } else {
            fprintf(stderr, "Unexpected extra argument: %s\n", argv[i]);
            print_usage(argv[0]);
            return 2;
        }
    }

    char udid_buf[64] = {0};
    if (!iphone_udid) {
        idevice_info_t *devices = NULL;
        int count = 0;

        if (idevice_get_device_list_extended(&devices, &count) != IDEVICE_E_SUCCESS || count == 0) {
            fprintf(stderr, "No iPhone found. Is it on the same Wi-Fi network?\n");
            print_usage(argv[0]);
            return 1;
        }

        int selected = 0;
        for (int i = 0; i < count; i++) {
            if (devices[i]->conn_type == CONNECTION_NETWORK) {
                selected = i;
                break;
            }
        }

        const char *conn_name = idevice_connection_name(devices[selected]->conn_type);
        strncpy(udid_buf, devices[selected]->udid, sizeof(udid_buf) - 1);
        fprintf(stderr, "Auto-selected device %s via %s\n", udid_buf, conn_name);

        idevice_device_list_extended_free(devices);
        iphone_udid = udid_buf;
    }

    idevice_t device = NULL;
    companion_proxy_client_t proxy = NULL;
    plist_t registry = NULL;
    int ret = 1;
    int printed = 0;
    uint32_t candidate_count = 0;

    const int lookup_options = IDEVICE_LOOKUP_USBMUX | IDEVICE_LOOKUP_NETWORK | IDEVICE_LOOKUP_PREFER_NETWORK;
    idevice_error_t ierr = idevice_new_with_options(&device, iphone_udid, lookup_options);
    if (ierr != IDEVICE_E_SUCCESS) {
        fprintf(stderr, "Error: Cannot connect to iPhone %s (err=%d)\n", iphone_udid, ierr);
        goto cleanup;
    }

    if (start_proxy(device, &proxy) != 0) {
        goto cleanup;
    }

    companion_proxy_error_t perr = companion_proxy_get_device_registry(proxy, &registry);
    if (perr != COMPANION_PROXY_E_SUCCESS) {
        if (perr == COMPANION_PROXY_E_NO_DEVICES) {
            if (json_output) {
                printf("{\"iphone_udid\":");
                print_json_escape(stdout, iphone_udid);
                printf(",\"devices\":[]}\n");
            } else {
                printf("No paired Watch found.\n");
            }
            ret = 0;
        } else {
            fprintf(stderr, "Error: Cannot get device registry: %s (%d)\n", companion_proxy_error_name(perr), perr);
        }
        goto cleanup;
    }

    if (!PLIST_IS_ARRAY(registry)) {
        fprintf(stderr, "Error: Unexpected registry response format\n");
        ret = 1;
        goto cleanup;
    }

    candidate_count = plist_array_get_size(registry);
    if (!json_output) {
        fprintf(stderr, "Registry returned %u devices\n", candidate_count);
    }

    if (candidate_count == 0) {
        if (json_output) {
            printf("{\"iphone_udid\":");
            print_json_escape(stdout, iphone_udid);
            printf(",\"devices\":[]}\n");
        } else {
            printf("No paired devices returned.\n");
        }
        ret = 0;
        goto cleanup;
    }

    if (json_output) {
        printf("{\"iphone_udid\":");
        print_json_escape(stdout, iphone_udid);
        printf(",\"devices\":[");
    }

    for (uint32_t i = 0; i < candidate_count; i++) {
        plist_t item = plist_array_get_item(registry, i);
        char *watch_udid = NULL;
        plist_get_string_val(item, &watch_udid);
        if (!watch_udid) {
            continue;
        }

        watch_device_info_t *info = collect_watch_info(device, watch_udid);
        if (!info) {
            plist_mem_free(watch_udid);
            continue;
        }

        if (watch_only && !info->is_watch) {
            free_watch_info(info);
            plist_mem_free(watch_udid);
            continue;
        }

        if (json_output) {
            print_json_device(stdout, info, printed == 0, watch_only);
            printed++;
        } else {
            if (!watch_only || info->is_watch) {
                print_human_device(info);
            }
            if (info->has_battery || !watch_only) {
                printed++;
            }
        }

        free_watch_info(info);
        plist_mem_free(watch_udid);
    }

    if (json_output) {
        printf("]}");
        if (printed == 0) {
            fputc('\n', stdout);
        } else {
            printf("\n");
        }
    }

    ret = 0;

cleanup:
    if (registry)
        plist_free(registry);
    if (proxy)
        companion_proxy_client_free(proxy);
    if (device)
        idevice_free(device);

    if (ret != 0 && !json_output) {
        fprintf(stderr, "Failed\n");
    }

    return ret;
}
