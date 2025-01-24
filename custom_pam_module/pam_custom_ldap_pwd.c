#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <string.h>
#include <ldap.h>
#include <unistd.h>

#include <syslog.h>
#include <stdlib.h>
#include <stdio.h>
#include <pwd.h>
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

static LDAP *ldap_handle = NULL;

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
    /*char **uid = ldap_get_values(ldap_handle, entry, "sAMAccountName");
    printf("sAMAccountName %s\n",*uid);
    char **uidNumber = ldap_get_values(ldap_handle, entry, "uidNumber");
    char **gidNumber = ldap_get_values(ldap_handle, entry, "gidNumber");
    char **homeDirectory = ldap_get_values(ldap_handle, entry, "homeDirectory");
    char **loginShell = ldap_get_values(ldap_handle, entry, "loginShell");

    if (uid && uidNumber && gidNumber && homeDirectory && loginShell) {
        pwd->pw_name = strdup(uid[0]);
        pwd->pw_uid = atoi(uidNumber[0]);
        pwd->pw_gid = atoi(gidNumber[0]);
        pwd->pw_dir = strdup(homeDirectory[0]);
        pwd->pw_shell = strdup(loginShell[0]);
        pwd->pw_passwd = "x"; // or use a hashed password if you store it

        ldap_value_free(uid);
        ldap_value_free(uidNumber);
        ldap_value_free(gidNumber);
        ldap_value_free(homeDirectory);
        ldap_value_free(loginShell);
    } else {
        ldap_msgfree(res);
        ldap_memfree(dn);
        return -1;
    }
    */
    // ldap_memfree(dn);
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

        // pam_syslog(pamh, LOG_DEBUG, "PAM_RHOST: %s\n", rhost);
        // pam_syslog(pamh, LOG_DEBUG, "SSH Connection Port: %s\n", port);

        /*
  linenr++;
    char *prefix = "PAM_RHOST=";
    if (strncmp(line, prefix, strlen(prefix)) == 0) {
        free(last_ip);
        last_ip = strdup(line + strlen(prefix));
        // Remove newline character from the end
        last_ip[strcspn(last_ip, "\n")] = '\0';
       // Log the extracted IP address
        printf("Extracted IP from line %d: %s", linenr, last_ip);
    }


    char *ssh_prefix = "SSH_CONNECTION=";

    if (strncmp(line, ssh_prefix, strlen(ssh_prefix)) == 0) {
            free(last_ssh_con);
            last_ssh_con = strdup(line + strlen(ssh_prefix));
            last_ssh_con[strcspn(last_ssh_con, "\n")] = '\0';
            printf("Extracted SSH CON from line %d: %s", linenr, last_ssh_con);
            pam_syslog(pamh, LOG_DEBUG, "Extracted SSH CONN from line %d: %s", linenr, last_ssh_con);
    }*/
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

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{

    const char *ssh_connection;
    const char *ssh_connection_env_var = "SSH_CONNECTION";
    char buffer[MAX_STRING_LENGTH] = "";
    int i = 0;
    char source_host[16] = {0};
    char source_port[6] = {0};
    // Get PAM_RHOST environment variable
    ssh_connection = pam_getenv(pamh, ssh_connection_env_var);
    // pam_syslog(pamh, LOG_DEBUG, "Remote host in PAM %s\n", ssh_connection);
    if (ssh_connection)
    {
        snprintf(buffer, sizeof(buffer), "Remote Host: %s\n", ssh_connection);
        char *ssh_connection_copy;
        char *token;
        char tokens[MAX_TOKENS][MAX_TOKEN_LENGTH];

        // Allocate memory for the string copy
        ssh_connection_copy = strdup(ssh_connection);
        if (ssh_connection_copy == NULL)
        {
            pam_syslog(pamh, LOG_DEBUG, "Error copying the ssh_connection %s\n", ssh_connection);
        }

        // Tokenize the string
        token = strtok(ssh_connection_copy, " ");
        while (token != NULL && i < MAX_TOKENS)
        {
            strncpy(tokens[i], token, MAX_TOKEN_LENGTH - 1);
            tokens[i][MAX_TOKEN_LENGTH - 1] = '\0'; // Ensure null termination
            i++;
            token = strtok(NULL, " ");
        }

        // Identify source IP
        // get_last_ip_address(pamh, source_host, source_port);
        strncpy(source_host, tokens[0], 16);
        strncpy(source_port, tokens[1], 6);
        if (source_host == NULL)
        {
            pam_syslog(pamh, LOG_DEBUG, "Failed to retrieve the last IP address from the log file");
            // return PAM_AUTH_ERR;
        }
        // Store the source IP in a variable
        pam_syslog(pamh, LOG_DEBUG, "Source IP: %s", source_host);
    }
    else
    {
        // sprintf(buffer, sizeof(buffer), "PAM_RHOST not set\n");
        pam_syslog(pamh, LOG_DEBUG, "PAM_RHOST not set");
    }
    const char *user;
    const char *pass;
    int retval;

    char *attribute;
    BerElement *ber;
    char **values;
    i = 0;

    // Get the username
    retval = pam_get_user(pamh, &user, NULL);
    if (retval != PAM_SUCCESS)
    {
        return retval;
    }

    if (strcmp("root", user) == 0)
    {
        pam_syslog(pamh, LOG_DEBUG, "This is root user %s", user);

        // Get the password from the user
        // retval = get_password(pamh, &pass);
        /*if (retval != PAM_SUCCESS) {
                return PAM_SUCCESS;

        } */
        return PAM_SUCCESS;
    }
    else if (getpwnam(user) != NULL)
    {
        char *s;
        int len;
        char command[100];
        char line[LINE_BUFSIZE];
        FILE *output;
        /*char source_host[16]= {0};
        char source_port[6] = {0};
        // Identify source IP
        //get_last_ip_address(pamh, source_host, source_port);
        strncpy(source_host, tokens[0], 16);
        strncpy(source_port, tokens[1], 6);
        if (source_host == NULL) {
                pam_syslog(pamh, LOG_DEBUG,"Failed to retrieve the last IP address from the log file");
                return PAM_AUTH_ERR;
        }

        // Store the source IP in a variable
        pam_syslog(pamh,LOG_DEBUG, "Source IP LOCAL : %s", source_host);
        */

        len = snprintf(command, sizeof(command), "/bin/bash ${cwd}/did.sh %s %s %s", user, source_host, source_port);
        output = popen(command, "r"); // update this location based on user path , and copy the script inside src/ to user path (if reqd)

        if (output == NULL)
        {
            pam_syslog(pamh, LOG_DEBUG, "POPEN: Failed to execute\n");
        }
        else
        {
            int count = 1;

            while (fgets(line, LINE_BUFSIZE - 1, output) != NULL)
            {
                pam_syslog(pamh, LOG_DEBUG, "Execution Result %s", line);
                s = myStrStr(line, "\"isValid\"\:true");
                if (s)
                {
                    pam_syslog(pamh, LOG_DEBUG, "DID Authentication Successful !%d", s);
                    return PAM_SUCCESS;
                }
            }
        }

        return PAM_SUCCESS;
    }
    else
    {
        pam_syslog(pamh, LOG_DEBUG, "%s not found in the system", user);
        if (init_ldap() != 0)
            return PAM_AUTHINFO_UNAVAIL;

        pam_syslog(pamh, LOG_DEBUG, "Init LDAP");
        char filter[256];
        snprintf(filter, sizeof(filter), LDAP_SEARCH_FILTER, user);
        pam_syslog(pamh, LOG_DEBUG, "Filter %s", filter);
        LDAPMessage *res, *entry;
        retval = ldap_search_ext_s(ldap_handle, BASE_DN, LDAP_SCOPE_SUBTREE, filter, NULL, 0, NULL, NULL, NULL, 0, &res);
        pam_syslog(pamh, LOG_DEBUG, "Ret VAL %d", retval);
        if (retval != LDAP_SUCCESS)
            return PAM_USER_UNKNOWN;

        entry = ldap_first_entry(ldap_handle, res);
        if (entry == NULL)
        {
            ldap_msgfree(res);
            pam_syslog(pamh, LOG_DEBUG, "%s not found in LDAP", user);
            return PAM_USER_UNKNOWN;
        }

        char *dn = ldap_get_dn(ldap_handle, entry);
        ldap_msgfree(res);
        if (!dn)
            return PAM_AUTHINFO_UNAVAIL;

        pam_syslog(pamh, LOG_DEBUG, "Username: %s, Password: %s, DN: %s", user, pass, dn);
        // retval = ldap_simple_bind_s(ldap_handle, dn, pass);
        ldap_memfree(dn);
        printf("LDAP_SUCCESS VALUE %d\n", retval);

        if (retval == LDAP_SUCCESS)
        {
            pam_syslog(pamh, LOG_DEBUG, "LDAP_SUCCESS %d", retval);
            struct passwd *pwd = malloc(sizeof(struct passwd));
            if (pwd == NULL)
            {
                return PAM_BUF_ERR;
            }
            char *buffer = malloc(1024 * sizeof(char));
            if (buffer == NULL)
            {
                free(pwd);
                return PAM_BUF_ERR;
            }
            pam_syslog(pamh, LOG_DEBUG, "Trace %d", 0);
            // int user_local = get_ldap_user_local(user, pwd, buffer, 1024);
            // pam_syslog(pamh, LOG_DEBUG, "get_ldap_user %d", user_local);
            if (get_ldap_user_local(user, pwd, buffer, 1024) == 0)
            {
                // Create local user if authentication is successful
                // pam_syslog(pamh,LOG_DEBUG, "create local user %d", create_local_user(user, pwd));

                // Check if the local user exists
                // struct passwd *local_user = getpwnam(user);
                if (/*local_user == NULL && */ create_local_user(user, pwd) != 0)
                {
                    free(pwd);
                    free(buffer);
                    return PAM_PERM_DENIED;
                }

                char *s;
                int len;
                char command[100];
                char line[LINE_BUFSIZE];
                FILE *output;

                /*char source_host[16] = {0};
                char source_port[6] = {0};

                // Identify source IP
                //get_last_ip_address(pamh, source_host, source_port);
                strncpy(source_host, tokens[0], 16);
                strncpy(source_port, tokens[1], 6);
                if (source_host == NULL) {
                        pam_syslog(pamh, LOG_DEBUG,"Failed to retrieve the last IP address from the log file");
                        return PAM_AUTH_ERR;
                }

                // Store the source IP in a variable
                pam_syslog(pamh,LOG_DEBUG, "Source IP: %s", source_host);
                */

                len = snprintf(command, sizeof(command), "/bin/bash ${cwd}/did.sh %s %s %s", user, source_host, source_port);
                output = popen(command, "r"); // update this location based on user path , and copy the script inside src/ to user path (if reqd)

                if (output == NULL)
                {
                    pam_syslog(pamh, LOG_DEBUG, "POPEN: Failed to execute\n");
                }
                else
                {
                    int count = 1;

                    while (fgets(line, LINE_BUFSIZE - 1, output) != NULL)
                    {
                        pam_syslog(pamh, LOG_DEBUG, "Execution Result %s", line);
                        // s = myStrStr(line,"\"isValid\":\"true\"");
                        s = myStrStr(line, "\"isValid\"\:true");
                        if (s)
                        {
                            pam_syslog(pamh, LOG_DEBUG, "DID Authentication Successful !%d", s);
                            return PAM_SUCCESS;
                        }
                    }
                }

                return PAM_SUCCESS;
            }
            else
            {
                free(pwd);
                free(buffer);
                // return PAM_USER_UNKNOWN;
                return PAM_SUCCESS;
            }
            free(pwd);
            free(buffer);
            return LDAP_SUCCESS;
        }
        else
        {
            return PAM_AUTH_ERR;
            // return PAM_SUCCESS;
        }
    }
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