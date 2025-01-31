#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <string.h>
#include <ldap.h>
#include <unistd.h>
#include <curl/curl.h>
#include <uuid/uuid.h>
#include <json-c/json.h>
#include <syslog.h>
#include <stdlib.h>
#include <stdio.h>
#include <pwd.h>
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/buffer.h>
// #include "ldap_utils.h" // Include the common header

#define LINE_BUFSIZE 128
#define LDAP_URI "ldap://10.150.67.225:389"
#define BASE_DN "cn=Users,dc=testad,dc=com"
#define LDAP_BIND_DN "cn=Administrator,cn=Users,dc=testad,dc=com"
#define LDAP_BIND_PW "Test@123"
#define LDAP_SEARCH_FILTER "(sAMAccountName=%s)"
#define LOG_FILE_PATH "/var/log/pam_rhost.log"
#define MAX_STRING_LENGTH 256
#define MAX_TOKENS 3
#define MAX_TOKEN_LENGTH 16
#define MAX_PAYLOAD_SIZE 2048

static LDAP *ldap_handle = NULL;

struct Memory
{
    char *response;
    // char *memory;
    size_t size;
};

// Callback function to handle the response data
static size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;
    struct Memory *mem = (struct Memory *)userp;

    char *ptr = realloc(mem->response, mem->size + realsize + 1);
    if (ptr == NULL)
    {
        fprintf(stderr, "Not enough memory to allocate buffer.\n");
        return 0;
    }

    mem->response = ptr;
    memcpy(&(mem->response[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->response[mem->size] = '\0';

    return realsize;
}

static int init_ldap()
{
    if (ldap_handle == NULL)
    {
        int ret = ldap_initialize(&ldap_handle, LDAP_URI);
        if (ret != LDAP_SUCCESS)
        {
            ldap_handle = NULL;
            return -1;
        }

        ret = ldap_simple_bind_s(ldap_handle, LDAP_BIND_DN, LDAP_BIND_PW);
        if (ret != LDAP_SUCCESS)
        {
            ldap_unbind_ext_s(ldap_handle, NULL, NULL);
            ldap_handle = NULL;
            return -1;
        }
    }
    return 0;
}

static int get_password(pam_handle_t *pamh, const char **password)
{
    int retval;
    struct pam_conv *conv;
    struct pam_message msg;
    const struct pam_message *msgp;
    struct pam_response *resp;

    retval = pam_get_item(pamh, PAM_CONV, (const void **)&conv);
    if (retval != PAM_SUCCESS)
    {
        return retval;
    }

    msg.msg_style = PAM_PROMPT_ECHO_OFF;
    msg.msg = "Password: ";
    msgp = &msg;
    resp = NULL;

    retval = conv->conv(1, &msgp, &resp, conv->appdata_ptr);
    if (retval != PAM_SUCCESS)
    {
        return retval;
    }

    if (resp)
    {
        if (resp->resp == NULL)
        {
            retval = PAM_CONV_ERR;
        }
        else
        {
            *password = resp->resp;
        }
        free(resp);
    }
    else
    {
        retval = PAM_CONV_ERR;
    }

    return retval;
}

static int create_local_user(const char *username, struct passwd *pwd)
{
    char cmd[1024];
    // snprintf(cmd, sizeof(cmd), "useradd -m -u %d -g %d -d %s -s %s %s",
    //         pwd->pw_uid, pwd->pw_gid, pwd->pw_dir, pwd->pw_shell, username);
    snprintf(cmd, sizeof(cmd), "useradd %s", username);
    // return system(cmd);
    return 0;
}

int get_ldap_user_local(const char *username, struct passwd *pwd, char *buffer, size_t buflen)
{
    if (init_ldap() != 0)
        return -1;

    printf("Trace 1\n");
    char filter[256];
    char *attribute = "";
    BerElement *ber = NULL;
    snprintf(filter, sizeof(filter), LDAP_SEARCH_FILTER, username);

    LDAPMessage *res, *entry;

    char *attrs[] = {"dn", "sAMAccountName", NULL}; // Attributes to retrieve
    int retval = ldap_search_ext_s(ldap_handle, BASE_DN, LDAP_SCOPE_SUBTREE, filter, attrs, 0, NULL, NULL, NULL, 0, &res);
    if (retval != LDAP_SUCCESS)
        return -1;

    entry = ldap_first_entry(ldap_handle, res);
    if (entry == NULL)
    {
        ldap_msgfree(res);
        return -1;
    }

    for (entry = ldap_first_entry(ldap_handle, res); entry != NULL; entry = ldap_next_entry(ldap_handle, entry))
    {
        char *dn = ldap_get_dn(ldap_handle, entry);
        if (!dn)
        {
            ldap_msgfree(res);
            return -1;
        }

        for (attribute = ldap_first_attribute(ldap_handle, res, &ber); attribute != NULL; attribute = ldap_next_attribute(ldap_handle, res, ber))
        {
            if (attribute == NULL)
            {
                fprintf(stderr, "ldap_first_attribute or ldap_next_attribute returned NULL\n");
                continue;
            }
            struct berval **values = ldap_get_values_len(ldap_handle, entry, "sAMAccountName");
            char *value = NULL;

            for (int i = 0; values[i] != NULL; ++i)
            {
                value = malloc(values[i]->bv_len + 1);
                strncpy(value, values[i]->bv_val, values[i]->bv_len);
                value[values[i]->bv_len] = '\0';
                printf("Value %s\n", value);
                pwd->pw_name = strdup(value);
                pwd->pw_uid = 1024;
                pwd->pw_gid = 1024;
                // strncopy(pwd->pw_dir, "/home/", pwd->pw_name);
                pwd->pw_dir = "/home/ldapuser";
                pwd->pw_shell = "/bin/sh";
                pwd->pw_passwd = "x";
                free(value);
            }
        }
    }
    ldap_msgfree(res);

    return 0;
}

// Function to extract PAM_RHOST and SSH_CONNECTION port
void extract_info(const char *input, char *rhost, char *port)
{
    const char *ptr = input;
    const char *end;
    char buffer[MAX_STRING_LENGTH];

    // Extract PAM_RHOST
    ptr = strstr(ptr, "PAM_RHOST=");
    if (ptr)
    {
        ptr += strlen("PAM_RHOST=");
        end = strchr(ptr, ' ');
        if (end == NULL)
            end = ptr + strlen(ptr); // end of string
        strncpy(rhost, ptr, end - ptr);
        rhost[end - ptr] = '\0'; // Null-terminate the string
    }
    else
    {
        strcpy(rhost, "Not found");
    }

    // Extract SSH_CONNECTION port
    ptr = strstr(input, "SSH_CONNECTION=");
    if (ptr)
    {
        ptr += strlen("SSH_CONNECTION=");
        // Skip IP addresses
        for (int i = 1; i < 2; i++)
        {
            end = strchr(ptr, ' ');
            if (end == NULL)
                end = ptr + strlen(ptr); // end of string
            ptr = end + 1;
        }
        end = strchr(ptr, ' ');
        if (end == NULL)
            end = ptr + strlen(ptr); // end of string
        strncpy(port, ptr, end - ptr);
        port[end - ptr] = '\0'; // Null-terminate the string
    }
    else
    {
        strcpy(port, "Not found");
    }
}

void get_last_ip_address(pam_handle_t *pamh, char *source, char *source_port)
{
    FILE *file = fopen(LOG_FILE_PATH, "r");
    if (!file)
    {
        return NULL;
    }
    int linenr = 0;
    char *last_ip = NULL;
    char *last_ssh_con = NULL;
    char line[LINE_BUFSIZE];

    char rhost[MAX_STRING_LENGTH];
    char port[MAX_STRING_LENGTH];
    while (fgets(line, sizeof(line), file))
    {

        extract_info(line, rhost, port);
    }

    fclose(file);
    strncpy(source, rhost, 16);
    strncpy(source_port, port, 6);
    // return last_ip;
}

// Function to parse arguments
void parse_arguments(int argc, const char **argv, char *remote_host)
{
    for (int i = 0; i < argc; i++)
    {
        if (strncmp(argv[i], "remote_host=", 12) == 0)
        {
            strncpy(remote_host, argv[i] + 12, 256 - 1);
            remote_host[256 - 1] = '\0';
        }
    }
}
// Function to write the response to a buffer
struct MemoryStruct
{
    char *memory;
    size_t size;
};

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;
    struct MemoryStruct *mem = (struct MemoryStruct *)userp;

    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
    if (ptr == NULL)
    {
        // send_logs("not enough memory (realloc returned NULL)\n");
        return 0;
    }

    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;

    return realsize;
}

// Function to Base64-encode a string
char *base64_encode(const char *input, int length)
{
    BIO *b64, *bmem;
    BUF_MEM *bptr;

    b64 = BIO_new(BIO_f_base64());
    bmem = BIO_new(BIO_s_mem());
    b64 = BIO_push(b64, bmem);
    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL); // Ignore newlines
    BIO_write(b64, input, length);
    BIO_flush(b64);
    BIO_get_mem_ptr(b64, &bptr);

    char *encoded = (char *)malloc(bptr->length + 1);
    memcpy(encoded, bptr->data, bptr->length);
    encoded[bptr->length] = '\0';

    BIO_free_all(b64);

    return encoded;
}

// Function to create the Authorization header
char *create_auth_header(pam_handle_t *pamh, const char *clientID, const char *clientSecret)
{
    // Concatenate clientID and clientSecret with ":"
    size_t input_length = strlen(clientID) + strlen(clientSecret) + 2; // 1 for ":" and 1 for '\0'
    char *input = (char *)malloc(input_length);
    snprintf(input, input_length, "%s:%s", clientID, clientSecret);

    // Base64-encode the concatenated string
    char *encoded = base64_encode(input, strlen(input));
    pam_syslog(pamh, LOG_DEBUG, "Encoded: %s\n", encoded);
    free(input);

    // Prepend "Basic " to the encoded string
    size_t header_length = strlen("Basic ") + strlen(encoded) + 1;
    char *auth_header = (char *)malloc(header_length);
    snprintf(auth_header, header_length, "Basic %s", encoded);
    free(encoded);

    pam_syslog(pamh, LOG_DEBUG, "Authorization Header: %s\n", auth_header);
    return auth_header;
}

// Function to fetch the token
char *FetchToken(pam_handle_t *pamh, const char *ssp, const char *tenantName, const char *clientID, const char *clientSecret)
{
    CURL *curl;
    CURLcode res;

    // Prepare the URL
    char tokenURL[512];
    snprintf(tokenURL, sizeof(tokenURL), "%s%s/oauth2/v1/token", ssp, tenantName);
    // printf("Token URL: %s\n", tokenURL);

    // Prepare the Basic Auth header
    char auth[256];
    snprintf(auth, sizeof(auth), "%s:%s", clientID, clientSecret);
    char authHeader[512];
    char *auth_header = create_auth_header(pamh, clientID, clientSecret);
    snprintf(authHeader, sizeof(authHeader), "Authorization: %s", auth_header);
    // printf("Authorization Header: %s\n", authHeader);

    // Prepare form data
    const char *formData = "grant_type=client_credentials&scope=urn:iam:myscopes";

    // Initialize the memory structure to hold the response
    struct MemoryStruct chunk;
    chunk.memory = malloc(1); // will grow as needed by the realloc above
    chunk.size = 0;           // no data at this point

    // Initialize libcurl
    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    if (!curl)
    {
        // send_logs("Failed to initialize CURL\n");
        pam_syslog(pamh, LOG_DEBUG, "Failed to initialize CURL\n");
        return NULL;
    }

    // Set CURL options
    curl_easy_setopt(curl, CURLOPT_URL, tokenURL);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, formData);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);

    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
    headers = curl_slist_append(headers, authHeader);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    // Perform the request
    res = curl_easy_perform(curl);
    if (res != CURLE_OK)
    {
        // send_logs("curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        pam_syslog(pamh, LOG_DEBUG, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        return NULL;
    }

    // Parse the response JSON
    struct json_object *parsed_json;
    struct json_object *access_token;
    parsed_json = json_tokener_parse(chunk.memory);
    pam_syslog(pamh, LOG_DEBUG, "Response: %s\n", chunk.memory);

    if (!json_object_is_type(parsed_json, json_type_object))
    {
        // send_logs("Failed to parse JSON response\n");
        pam_syslog(pamh, LOG_DEBUG, "Failed to parse JSON response\n");
        return NULL;
    }
    pam_syslog(pamh, LOG_DEBUG, "Before Parsing access_token\n");
    if (json_object_object_get_ex(parsed_json, "access_token", &access_token))
    {
        const char *token = json_object_get_string(access_token);
        pam_syslog(pamh, LOG_DEBUG, "Access Token: %s\n", token);
        char *result = strdup(token);
        pam_syslog(pamh, LOG_DEBUG, "Result: %s\n", result);
        json_object_put(parsed_json);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        free(chunk.memory);
        return result;
    }
    else
    {
        // send_logs("access_token not found in the response\n");
        pam_syslog(pamh, LOG_DEBUG, "access_token not found in the response\n");
        json_object_put(parsed_json);
    }

    // Cleanup
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    curl_global_cleanup();
    free(chunk.memory);
    free(auth_header);

    return NULL;
}

// Function to execute external API call
int external_call_api(const char *user, const char *source_ip, const char *source_port, const char *access_token)
{
    char hostname[256];
    char group_buffer[1024];
    char groups[512] = {0};
    char credential_type[64] = {0};
    uuid_t bin_uuid;
    char uuid[37]; // UUID is 36 characters + null terminator
    char payload[MAX_PAYLOAD_SIZE];
    struct passwd *pw;
    int user_id;

    // Get hostname
    if (gethostname(hostname, sizeof(hostname)) != 0)
    {
        perror("gethostname");
        return -1;
    }

    // Get groups for the user
    snprintf(group_buffer, sizeof(group_buffer), "id -Gn %s", user);
    FILE *group_fp = popen(group_buffer, "r");
    if (group_fp)
    {
        if (fgets(groups, sizeof(groups), group_fp) == NULL)
        {
            fprintf(stderr, "Failed to get groups for user: %s\n", user);
        }
        pclose(group_fp);
    }

    // Get user ID
    pw = getpwnam(user);
    if (!pw)
    {
        fprintf(stderr, "User %s not found\n", user);
        strcpy(credential_type, "AD");
    }
    else
    {
        user_id = pw->pw_uid;
        if (user_id >= 1 && user_id <= 999)
        {
            strcpy(credential_type, "ServiceAccount");
        }
        else
        {
            strcpy(credential_type, "SSH");
        }
    }

    // Generate UUID
    uuid_generate_random(bin_uuid);
    uuid_unparse(bin_uuid, uuid);

    // Construct JSON payload
    snprintf(payload, sizeof(payload),
             "{"
             "\"username\": \"%s\","
             "\"credentialType\": \"%s\","
             "\"hostname\": \"%s\","
             "\"groupName\": \"%s\","
             "\"requestId\": \"%s\","
             "\"sourceIp\": \"%s\","
             "\"port\": \"%s\""
             "}",
             user, credential_type, hostname, groups, uuid, source_ip, source_port);

    printf("Payload: %s\n", payload);

    // Make API call using libcurl
    CURL *curl = curl_easy_init();
    if (curl)
    {
        CURLcode res;
        struct curl_slist *headers = NULL;

        char auth_header[512];

        snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", access_token);
        headers = curl_slist_append(headers, "Content-Type: application/json");
        headers = curl_slist_append(headers, auth_header);

        curl_easy_setopt(curl, CURLOPT_URL, "https://ssp.test-31.dev-ssp.com/default/pwlessauthn/v1/client/auth/api/v3/do-authenticationV4");
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload);

        res = curl_easy_perform(curl);
        if (res != CURLE_OK)
        {
            fprintf(stderr, "Curl request failed: %s\n", curl_easy_strerror(res));
            curl_slist_free_all(headers);
            curl_easy_cleanup(curl);
            return -1; // API call failed
        }
        else
        {
            printf("API call successful.\n");
        }

        // Cleanup
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
    }
    else
    {
        fprintf(stderr, "Curl initialization failed.\n");
        return -1;
    }

    return 0; // API call successful
}

// Helper function to get a parameter value
static const char *get_pam_param(int argc, const char **argv, const char *key)
{
    for (int i = 0; i < argc; i++)
    {
        if (strncmp(argv[i], key, strlen(key)) == 0 && argv[i][strlen(key)] == '=')
        {
            return argv[i] + strlen(key) + 1; // Return the value after '='
        }
    }
    return NULL;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
    const char *ssh_connection;
    const char *ssh_connection_env_var = "SSH_CONNECTION";
    char buffer[MAX_STRING_LENGTH] = "";
    int i = 0;
    char source_host[16] = {0};
    char source_port[6] = {0};

    const char *sspURL;
    const char *tenantName;
    const char *clientId;
    const char *clientSecret;

    ssh_connection = pam_getenv(pamh, ssh_connection_env_var);

    sspURL = get_pam_param(argc, argv, "ssp");
    tenantName = get_pam_param(argc, argv, "tenant");
    clientId = get_pam_param(argc, argv, "client_id");
    clientSecret = get_pam_param(argc, argv, "secret");

    pam_syslog(pamh, LOG_DEBUG, "SSP URL: %s", sspURL);
    pam_syslog(pamh, LOG_DEBUG, "Tenant Name: %s", tenantName);
    pam_syslog(pamh, LOG_DEBUG, "Client ID: %s", clientId);
    pam_syslog(pamh, LOG_DEBUG, "Client Secret: %s", clientSecret);

    char *token = FetchToken(pamh, sspURL, tenantName, clientId, clientSecret);

    if (token)
    {
        pam_syslog(pamh, LOG_DEBUG, "Token: %s\n", token);
        free(token); // Free the token after use
    }
    else
    {
        pam_syslog(pamh, LOG_DEBUG, "Failed to fetch token\n");
    }

    if (ssh_connection)
    {
        char *ssh_connection_copy;
        char *token;
        char tokens[MAX_TOKENS][MAX_TOKEN_LENGTH];

        ssh_connection_copy = strdup(ssh_connection);
        if (ssh_connection_copy == NULL)
        {
            pam_syslog(pamh, LOG_DEBUG, "Error copying ssh_connection: %s", ssh_connection);
        }

        token = strtok(ssh_connection_copy, " ");
        while (token != NULL && i < MAX_TOKENS)
        {
            strncpy(tokens[i], token, MAX_TOKEN_LENGTH - 1);
            tokens[i][MAX_TOKEN_LENGTH - 1] = '\0';
            i++;
            token = strtok(NULL, " ");
        }

        strncpy(source_host, tokens[0], 16);
        strncpy(source_port, tokens[1], 6);

        if (source_host == NULL)
        {
            pam_syslog(pamh, LOG_DEBUG, "Failed to retrieve the source host.");
        }

        pam_syslog(pamh, LOG_DEBUG, "Source IP: %s", source_host);
    }
    else
    {
        pam_syslog(pamh, LOG_DEBUG, "PAM_RHOST not set");
    }

    const char *user;
    int retval = pam_get_user(pamh, &user, NULL);
    if (retval != PAM_SUCCESS)
    {
        return retval;
    }

    if (strcmp("root", user) == 0)
    {
        pam_syslog(pamh, LOG_DEBUG, "This is the root user: %s", user);
        return PAM_SUCCESS;
    }
    else if (getpwnam(user) != NULL)
    {
        pam_syslog(pamh, LOG_DEBUG, "Authenticated local user: %s", user);

        int api_result = external_call_api(user, source_host, source_port, token);
        if (api_result == 0)
        {
            pam_syslog(pamh, LOG_DEBUG, "DID Authentication Successful!");
            return PAM_SUCCESS;
        }
        else
        {
            pam_syslog(pamh, LOG_DEBUG, "DID Authentication Failed.");
            // return PAM_AUTH_ERR;
            return PAM_SUCCESS;
        }
    }
    else
    {
        pam_syslog(pamh, LOG_DEBUG, "%s not found in the system.", user);

        if (init_ldap() != 0)
        {
            return PAM_AUTHINFO_UNAVAIL;
        }

        char filter[256];
        snprintf(filter, sizeof(filter), LDAP_SEARCH_FILTER, user);
        pam_syslog(pamh, LOG_DEBUG, "Filter: %s", filter);

        LDAPMessage *res, *entry;
        retval = ldap_search_ext_s(ldap_handle, BASE_DN, LDAP_SCOPE_SUBTREE, filter, NULL, 0, NULL, NULL, NULL, 0, &res);
        if (retval != LDAP_SUCCESS)
        {
            return PAM_USER_UNKNOWN;
        }

        entry = ldap_first_entry(ldap_handle, res);
        if (entry == NULL)
        {
            ldap_msgfree(res);
            pam_syslog(pamh, LOG_DEBUG, "%s not found in LDAP.", user);
            return PAM_USER_UNKNOWN;
        }

        char *dn = ldap_get_dn(ldap_handle, entry);
        ldap_msgfree(res);
        if (!dn)
        {
            return PAM_AUTHINFO_UNAVAIL;
        }

        pam_syslog(pamh, LOG_DEBUG, "LDAP DN: %s", dn);

        struct passwd *pwd = malloc(sizeof(struct passwd));
        char *buffer = malloc(1024 * sizeof(char));
        if (!pwd || !buffer)
        {
            free(pwd);
            free(buffer);
            return PAM_BUF_ERR;
        }

        if (get_ldap_user_local(user, pwd, buffer, 1024) == 0)
        {
            if (create_local_user(user, pwd) != 0)
            {
                free(pwd);
                free(buffer);
                return PAM_PERM_DENIED;
            }

            int api_result = external_call_api(user, source_host, source_port, token);
            if (api_result == 0)
            {
                pam_syslog(pamh, LOG_DEBUG, "DID Authentication Successful!");
                free(pwd);
                free(buffer);
                return PAM_SUCCESS;
            }
            else
            {
                pam_syslog(pamh, LOG_DEBUG, "DID Authentication Failed.");
            }
        }

        free(pwd);
        free(buffer);
    }

    // return PAM_AUTH_ERR;
    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
    return PAM_SUCCESS;
}

// function definition
int myStrStr(char *str, char *sub)
{
    int flag = 0;

    int i = 0, len1 = 0, len2 = 0;

    len1 = strlen(str);
    len2 = strlen(sub);

    // printf("len1 %d, len2 %d\n", len1, len2);
    // printf("str : %c\n", str[0]);
    // printf("sub : %c\n", sub[0]);

    while (str[i] != '\0')
    {

        if (str[i] == sub[0])
        {
            if ((i + len2) > len1)
                break;

            if (strncmp(str + i, sub, len2) == 0)
            {
                flag = 1;
                break;
            }
        }
        i++;
    }

    return flag;
}