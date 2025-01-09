#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <dirent.h>
#include <curl/curl.h>
#include <pwd.h>
#include <json-c/json.h>
#include <utmp.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <signal.h>
#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/buffer.h>
#include <arpa/inet.h>
#include <ctype.h>
#include <syslog.h>
#include <stdarg.h>
#include <time.h>

#define PROC_NET_TCP "/proc/%d/net/tcp"
#define MAX_LINE_LENGTH 256
#define MAX_OUTPUT_SIZE 1024
#define INITIAL_OUTPUT_SIZE 1024
#define MAX_LINE_LENGTH 256
#define LOG_FILE "/var/log/ssp_agent.log"
#define PROC_PATH_LEN 256
#define LINK_TARGET_LEN 256
// Function to check if a process is associated with a TTY
int check_process_tty(pid_t pid)
{
    char proc_path[PROC_PATH_LEN];
    char link_target[LINK_TARGET_LEN];
    ssize_t len;

    // Construct the path to the standard input file descriptor of the process
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/fd/0", pid);

    // Read the symlink target
    len = readlink(proc_path, link_target, sizeof(link_target) - 1);
    if (len == -1)
    {
        perror("readlink");
        return 1;
    }

    // Null-terminate the string
    link_target[len] = '\0';

    // Check if the link target is a TTY
    if (strstr(link_target, "tty") != NULL || strstr(link_target, "pts") != NULL)
    {
        printf("Process %d is associated with a TTY: %s\n", pid, link_target);
        return 1;
    }
    else
    {
        printf("Process %d is not associated with a TTY (or TTY not detected).\n", pid);
        return 0;
    }
    return 1;
}

void send_logs(const char *format, ...)
{
    va_list args;
    char log_message[1024];

    // Format the log message
    va_start(args, format);
    vsnprintf(log_message, sizeof(log_message), format, args);
    va_end(args);

    // Write to syslog
    syslog(LOG_NOTICE, "%s", log_message);

    // Write to log file
    FILE *log_file = fopen(LOG_FILE, "a");
    if (log_file)
    {
        // Add a timestamp
        time_t now = time(NULL);
        char timestamp[64];
        strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", localtime(&now));
        fprintf(log_file, "[%s] %s", timestamp, log_message);
        fclose(log_file);
    }
    else
    {
        // If the log file can't be opened, log an error in syslog
        syslog(LOG_ERR, "Failed to open log file: %s", LOG_FILE);
    }
}

// Function to get the parent PID of a process
pid_t get_parent_pid(pid_t pid)
{
    char path[256], buf[256];
    FILE *fp;
    snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    if ((fp = fopen(path, "r")) != NULL)
    {
        if (fgets(buf, sizeof(buf), fp) != NULL)
        {
            fclose(fp);
            strtok(buf, " ");               // pid
            strtok(NULL, " ");              // comm
            strtok(NULL, " ");              // state
            return atoi(strtok(NULL, " ")); // ppid
        }
        fclose(fp);
    }
    return -1;
}
// Function to get the PIDs of all ssh processes
void get_ssh_pids(pid_t *pids, int *count)
{
    DIR *dir;
    struct dirent *entry;
    char path[256], buf[256];
    FILE *fp;
    *count = 0;

    if (!(dir = opendir("/proc")))
    {
        perror("opendir");
        return;
    }

    while ((entry = readdir(dir)) != NULL)
    {
        if (entry->d_type == DT_DIR)
        {
            pid_t pid = atoi(entry->d_name);
            if (pid > 0)
            {
                snprintf(path, sizeof(path), "/proc/%d/comm", pid);
                if ((fp = fopen(path, "r")) != NULL)
                {
                    if (fgets(buf, sizeof(buf), fp) != NULL)
                    {
                        buf[strcspn(buf, "\n")] = 0;
                        if (strcmp(buf, "ssh") == 0)
                        {
                            fclose(fp);
                            snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
                            if ((fp = fopen(path, "r")) != NULL)
                            {
                                if (fgets(buf, sizeof(buf), fp) != NULL)
                                {
                                    if (strstr(buf, "ssh") != NULL && strlen(buf) < 4)
                                    {
                                        // printf("buffer: %s\n",buf);
                                        pids[*count] = pid;
                                        (*count)++;
                                    }
                                }
                                fclose(fp);
                            }
                        }
                        else
                        {
                            fclose(fp);
                        }
                    }
                    else
                    {
                        fclose(fp);
                    }
                }
            }
        }
    }

    closedir(dir);
}

uid_t get_process_uid(pid_t pid)
{
    char path[256], buf[256];
    FILE *fp;
    snprintf(path, sizeof(path), "/proc/%d/status", pid);
    if ((fp = fopen(path, "r")) != NULL)
    {
        while (fgets(buf, sizeof(buf), fp) != NULL)
        {
            if (strncmp(buf, "Uid:", 4) == 0)
            {
                uid_t uid;
                if (sscanf(buf + 4, "%d", &uid) == 1)
                {
                    fclose(fp);
                    return uid;
                }
            }
        }
        fclose(fp);
    }
    return -1;
}

// Function to get the current session username
void get_current_session_user(uid_t uid, char *user)
{
    struct passwd *pw;

    pw = getpwuid(uid);
    if (pw == NULL)
    {
        perror("getpwuid");
        exit(EXIT_FAILURE);
    }
    strncpy(user, pw->pw_name, sizeof(user) - 1);
    user[sizeof(user) - 1] = '\0';
    // return pw->pw_name;
}

// Function to execute command and return output
char *run_command(const char *cmd)
{
    // printf("Trace 3\n");
    FILE *fp;
    size_t output_size = INITIAL_OUTPUT_SIZE;
    char *output = malloc(output_size);
    if (output == NULL)
    {
        perror("malloc");
        exit(EXIT_FAILURE);
    }

    // Open the command for reading
    fp = popen(cmd, "r");
    if (fp == NULL)
    {
        perror("popen");
        free(output);
        exit(EXIT_FAILURE);
    }

    // printf("Trace 2\n");
    //  Read the output into the buffer
    size_t index = 0;
    char line[MAX_LINE_LENGTH];
    while (fgets(line, sizeof(line), fp) != NULL)
    {
        // printf("LINE %s\n", line);
        size_t len = strlen(line);
        if (index + len >= output_size)
        {
            // Reallocate if necessary
            output_size *= 2;
            char *new_output = realloc(output, output_size);
            if (new_output == NULL)
            {
                perror("realloc");
                pclose(fp);
                free(output);
                exit(EXIT_FAILURE);
            }
            output = new_output;
        }
        strcpy(output + index, line);
        index += len;
    }

    // Null-terminate the string
    output[index] = '\0';

    // Close the pipe
    if (pclose(fp) == -1)
    {
        perror("pclose");
        free(output);
        exit(EXIT_FAILURE);
    }
    // printf("%s", output);
    return output;
}

// function to  fetch local port
void get_port(int pid, char *port, size_t size)
{
    char command[256];
    snprintf(command, sizeof(command), "ss -tanp | grep 'pid=%d'", pid);

    FILE *fp = popen(command, "r");
    if (!fp)
    {
        perror("popen");
        strncpy(port, "Unknown", size - 1);
        port[size - 1] = '\0';
        return;
    }

    char line[1024];
    if (fgets(line, sizeof(line), fp))
    {

        char *local_start = strchr(line, ':');
        if (local_start)
        {
            local_start++; // Move past ':'
            char *local_end = strchr(local_start, ' ');
            if (local_end)
            {
                size_t local_len = local_end - local_start;
                strncpy(port, local_start, local_len);
                port[local_len] = '\0'; // Null-terminate
            }
        }
    }

    pclose(fp);

    // Fallback if not found
    if (strlen(port) == 0)
    {
        strncpy(port, "Unknown", size - 1);
        port[size - 1] = '\0';
    }
}

// Updated get_cmdline function
void get_cmdline(int pid, char *cmdline, char *ssh_user, char *hostname, size_t size)
{
    char path[256];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);

    FILE *fp = fopen(path, "r");
    if (fp)
    {
        size_t bytes_read = fread(cmdline, 1, size - 1, fp);
        cmdline[bytes_read] = '\0'; // Null-terminate the buffer
        fclose(fp);

        // Initialize outputs
        ssh_user[0] = '\0';
        hostname[0] = '\0';

        // Iterate through the concatenated command line
        char *current = cmdline;
        while (*current)
        {
            if (strncmp(current, "-i", 2) == 0)
            {
                // Detect identity file flag (-i)
                current += 2; // Skip "-i"
                while (*current == ' ' || *current == '\0')
                    current++; // Skip spaces or nulls
                current += strlen(current) + 1;
            }
            else if (strchr(current, '@'))
            {
                // Detect user@hostname
                char *at_sign = strchr(current, '@');
                if (at_sign)
                {
                    strncpy(ssh_user, current, at_sign - current);
                    ssh_user[at_sign - current] = '\0'; // Null-terminate ssh_user

                    char *host_start = at_sign + 1;
                    char *host_end = host_start;
                    while (*host_end && *host_end != '-' && *host_end != ' ')
                        host_end++;
                    size_t host_len = host_end - host_start;
                    strncpy(hostname, host_start, host_len);
                    hostname[host_len] = '\0'; // Null-terminate hostname
                }
                current += strlen(current) + 1;
            }
            else
            {
                current += strlen(current) + 1; // Move to the next token
            }
        }
    }
    else
    {
        perror("fopen");
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
        send_logs("not enough memory (realloc returned NULL)\n");
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
char *create_auth_header(const char *clientID, const char *clientSecret)
{
    // Concatenate clientID and clientSecret with ":"
    size_t input_length = strlen(clientID) + strlen(clientSecret) + 2; // 1 for ":" and 1 for '\0'
    char *input = (char *)malloc(input_length);
    snprintf(input, input_length, "%s:%s", clientID, clientSecret);

    // Base64-encode the concatenated string
    char *encoded = base64_encode(input, strlen(input));
    free(input);

    // Prepend "Basic " to the encoded string
    size_t header_length = strlen("Basic ") + strlen(encoded) + 1;
    char *auth_header = (char *)malloc(header_length);
    snprintf(auth_header, header_length, "Basic %s", encoded);
    free(encoded);

    return auth_header;
}

// Function to fetch the token
char *FetchToken(const char *baseUrl, const char *tenantName, const char *clientID, const char *clientSecret)
{
    CURL *curl;
    CURLcode res;

    // Prepare the URL
    char tokenURL[512];
    snprintf(tokenURL, sizeof(tokenURL), "%s%s/oauth2/v1/token", baseUrl, tenantName);
    // printf("Token URL: %s\n", tokenURL);

    // Prepare the Basic Auth header
    char auth[256];
    snprintf(auth, sizeof(auth), "%s:%s", clientID, clientSecret);
    char authHeader[512];
    char *auth_header = create_auth_header(clientID, clientSecret);
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
        send_logs("Failed to initialize CURL\n");
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
        send_logs("curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        return NULL;
    }

    // Parse the response JSON
    struct json_object *parsed_json;
    struct json_object *access_token;
    parsed_json = json_tokener_parse(chunk.memory);
    if (!parsed_json)
    {
        send_logs("Failed to parse JSON response\n");
        return NULL;
    }

    if (json_object_object_get_ex(parsed_json, "access_token", &access_token))
    {
        const char *token = json_object_get_string(access_token);
        char *result = strdup(token);
        json_object_put(parsed_json);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        free(chunk.memory);
        return result;
    }
    else
    {
        send_logs("access_token not found in the response\n");
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

// void call_external_api(const char* user, const char* ssh_user, const char* dest_ip) {
int call_external_api(const char *user, const char *ssh_user, const char *source_hostname, const char *destination_hostname, const char *port, const char *method, int pid, const char *token, int isInteractive)
{
    // printf("Calling external API Start\n");
    CURL *curl;
    CURLcode res;
    struct curl_slist *headers = NULL;
    int ret = -1;
    struct MemoryStruct chunk;

    chunk.memory = malloc(1); // will be grown as needed by the realloc above
    chunk.size = 0;           // no data at this point

    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();
    if (curl)
    {
        // JSON payload
        char json_payload[256];
        snprintf(json_payload, sizeof(json_payload),
                 "{\"loggedInUserName\":\"%s\", \"sourceHostname\":\"%s\", \"loggingInUser\":\"%s\","
                 "\"destinationHostname\":\"%s\", \"credentialType\":\"%s\",\"accessMode\": \"%d\" ,\"port\": \"%s\"}",
                 user, source_hostname, ssh_user, destination_hostname, "ServiceAccount", isInteractive, port);
        // printf("JSON Payload: %s\n", json_payload);

        // Set URL
        curl_easy_setopt(curl, CURLOPT_URL, "https://ssp.test-31.dev-ssp.com:31913/default/pwlessauthn/v1/client/auth/api/v3/do-authenticationV4Step1");

        // Set JSON headers
        char auth[2048];
        snprintf(auth, sizeof(auth), "Authorization: Bearer %s", token);
        headers = curl_slist_append(headers, "Content-Type: application/json");
        headers = curl_slist_append(headers, auth);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

        // Set POST data
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json_payload);

        // Set write callback
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);

        // Perform the request
        res = curl_easy_perform(curl);
        if (res != CURLE_OK)
        {
            send_logs("curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        }
        else
        {
            // Parse the JSON response
            struct json_object *parsed_json;
            struct json_object *status;
            struct json_object *message;
            struct json_object *isValid;

            // printf("Raw Response: %s\n", chunk.memory);

            parsed_json = json_tokener_parse(chunk.memory);
            if (parsed_json == NULL)
            {
                send_logs("Error parsing JSON response\n");
            }
            else
            {
                json_object_object_get_ex(parsed_json, "status", &status);
                json_object_object_get_ex(parsed_json, "message", &message);
                json_object_object_get_ex(parsed_json, "isValid", &isValid);
                send_logs("Status: %s\n", json_object_get_string(status));
                send_logs("Message: %s\n", json_object_get_string(message));
                send_logs("IsValid: %s\n", json_object_get_string(isValid));
                ret = strcmp(json_object_get_string(isValid), "true");
                json_object_put(parsed_json);
            }
        }

        // Cleanup
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
    }

    curl_global_cleanup();
    if (ret == 0)
    {
        sleep(5);
        if (ptrace(PTRACE_DETACH, pid, NULL, NULL) == -1)
        {
            perror("ptrace detach");
            exit(EXIT_FAILURE);
        }
    }
    // printf("Calling external API Ends\n");
    free(chunk.memory);
    return ret;
}

// Updated extract_destination_ip_port to get the remote IP (source IP) and port
void get_public_ip(char *ip_address, size_t size)
{
    CURL *curl;
    CURLcode res;

    struct MemoryStruct chunk;
    chunk.memory = malloc(1); // Initial allocation
    chunk.size = 0;           // No data at first

    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    if (curl)
    {
        // Query the `ifconfig.me` service
        curl_easy_setopt(curl, CURLOPT_URL, "https://ifconfig.me/ip");
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);

        res = curl_easy_perform(curl);
        if (res != CURLE_OK)
        {
            send_logs("curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
            strncpy(ip_address, "Unknown", size - 1);
            ip_address[size - 1] = '\0';
        }
        else
        {
            strncpy(ip_address, chunk.memory, size - 1);
            ip_address[size - 1] = '\0'; // Null-terminate the result
        }

        // Cleanup
        curl_easy_cleanup(curl);
        free(chunk.memory);
    }
    else
    {
        send_logs("Failed to initialize curl.\n");
        strncpy(ip_address, "Unknown", size - 1);
        ip_address[size - 1] = '\0';
    }

    curl_global_cleanup();
}

// Function to get the terminal associated with a user
char *get_user_terminal(const char *user)
{
    struct utmp *ut;
    setutent();
    while ((ut = getutent()) != NULL)
    {
        if (ut->ut_type == USER_PROCESS && strncmp(ut->ut_user, user, UT_NAMESIZE) == 0)
        {
            endutent();
            return ut->ut_line;
        }
    }
    endutent();
    return NULL;
}
// Function to send a message to the user's terminal
void send_message_to_user(const char *user, const char *message)
{
    char *terminal = get_user_terminal(user);
    if (terminal)
    {
        char command[256];
        snprintf(command, sizeof(command), "echo '%s' | write %s", message, user);
        system(command);
    }
}

// Updated monitor_process function with sourceHostname integration
void monitor_process(pid_t pid, const char *token)
{
    int status;
    sleep(1);

    // Attach to the process
    if (ptrace(PTRACE_ATTACH, pid, NULL, NULL) == -1)
    {
        perror("ptrace attach");
        return;
    }

    waitpid(pid, &status, 0);

    if (WIFEXITED(status))
    {
        send_logs("Process %d exited\n", pid);
        return;
    }

    // Get the UID of the process
    uid_t uid = get_process_uid(pid);
    if (uid == -1)
    {
        send_logs("Failed to get UID for PID: %d\n", pid);
        return;
    }

    // Process command-line arguments
    char cmdline[1024] = {0};
    char source_hostname[256] = {0};
    char ssh_user[256] = {0};
    char destination_hostname[256] = {0};
    char port[16] = {0};
    char login_method[64] = {0};
    char user[64] = {0};

    // Get session user
    // get_current_session_user(uid, user);

    // parse_ssh_cmd(cmdline, ssh_user, hostname);
    get_cmdline(pid, cmdline, ssh_user, destination_hostname, sizeof(cmdline));
    get_port(pid, port, sizeof(port));
    get_public_ip(source_hostname, sizeof(source_hostname));
    int isInteractive = check_process_tty(pid);

    struct passwd pwd;
    struct passwd *result = NULL;
    char buffer[1024];

    int ret = getpwuid_r(uid, &pwd, buffer, sizeof(buffer), &result);
    if (ret != 0 || result == NULL)
    {
        fprintf(stderr, "getpwuid_r failed: %s\n", strerror(ret));
        return 1;
    }
    // Debug output
    send_logs("Monitoring SSH rocess:\n  PID: %d\n  Source Hostname: %s\n  Logged User: %s\n  SSH User: %s\n  SSH Hostname: %s\n  Port: %s\n  Login Method: %s\n  Access Mode: %s\n", pid, source_hostname, pwd.pw_name, ssh_user, destination_hostname, port, "ServiceAccount", (isInteractive == 1 ? "Interactive" : "Non Interactive"));
    // send_logs("  PID: %d\n", pid);
    // send_logs("  Source Hostname: %s\n", source_hostname);
    // send_logs("  Logged User: %s\n", user);
    // send_logs("  SSH User: %s\n", ssh_user);
    // send_logs("  SSH Hostname: %s\n", destination_hostname);
    // send_logs("  Port: %s\n", port);
    // send_logs("  Login Method: %s\n", "ServiceAccount");
    // send_logs("  Access Mode: %s\n", (isInteractive == 1 ? "Interactive" : "Non Interactive"));
    // Call the external API
    int isValid = call_external_api(pwd.pw_name, ssh_user, source_hostname, destination_hostname, port, login_method, pid, token, isInteractive);

    // Handle API response
    if (isValid != 0)
    {
        // If API validation fails, terminate the process
        send_logs("Terminating SSH process (PID: %d) due to invalid session.\n", pid);
        if (kill(pid, SIGKILL) == 0)
        {
            send_logs("SSH process (PID: %d) killed successfully.\n", pid);
        }
        else
        {
            perror("kill");
        }
    }

    // Detach from the process
    if (ptrace(PTRACE_DETACH, pid, NULL, NULL) == -1)
    {
        perror("ptrace detach");
    }
    else
    {
        send_logs("Process %d detached successfully.\n", pid);
    }
}

// Function to implement search operation
int findElement(int arr[], int n, int key)
{
    int i;
    for (i = 0; i < n; i++)
        if (arr[i] == key)
            return i;

    // If the key is not found
    return -1;
}
// Define a struct to hold the arguments
typedef struct
{
    int pid;
    char *token;
} ThreadArgs;

void *create_thread(void *arg)
{
    ThreadArgs *args = (ThreadArgs *)arg;
    // printf("Monitoring ssh process with PID %d\n", args->pid);
    monitor_process(args->pid, args->token);
    return NULL;
}

int main()
{
    pthread_t threads[1024];
    pid_t pids[1024];
    int count, tempCount, i;
    int processed[10] = {0};
    ThreadArgs thread_args[5];
    const char *baseUrl = "https://ssp.test-31.dev-ssp.com:31913/";
    const char *tenantName = "default";
    const char *clientID = "918003c0-d3bf-4b82-97e8-862043695914";
    const char *clientSecret = "7e979441-40cd-482e-9a19-4541d22880cd";

    char *token = FetchToken(baseUrl, tenantName, clientID, clientSecret);
    // printf("Token : %s\n", token);

    while (1)
    {
        get_ssh_pids(pids, &count);
        tempCount = count;

        // if (count == 0) {
        //     fprintf(stderr, "No ssh processes found\n");
        //     //exit(EXIT_FAILURE);
        // }
        if (count > tempCount || count < tempCount)
        {
            send_logs("New SSH process detected\n");
            tempCount = count;
        }
        // printf("Found %d ssh processes\n", count);
        for (i = 0; i < count; i++)
        {
            int n = sizeof(processed) / sizeof(processed[0]);

            if (pids[i] != 1392077)
            {
                int position = findElement(processed, n, pids[i]);
                if (position == -1)
                {
                    thread_args[i].pid = pids[i];
                    thread_args[i].token = token;
                    processed[i] = pids[i];
                    if (pthread_create(&threads[i], NULL, create_thread, &thread_args[i]) != 0)
                    {
                        perror("Failed to create thread");
                        return 1;
                    }
                }
            }
        }
        // sleep(1);
    }
    return 0;
}