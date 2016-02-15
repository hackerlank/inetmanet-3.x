%{
/*
 * Copyright 2013 Google Inc.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */
/*
 * Author: Author: ncardwell@google.com (Neal Cardwell)
 *
 * This is the parser for the packetdrill script language. It is
 * processed by the bison parser generator.
 *
 * For full documentation see: http://www.gnu.org/software/bison/manual/
 *
 * Here is a quick and dirty tutorial on bison:
 *
 * A bison parser specification is basically a BNF grammar for the
 * language you are parsing. Each rule specifies a nonterminal symbol
 * on the left-hand side and a sequence of terminal symbols (lexical
 * tokens) and or nonterminal symbols on the right-hand side that can
 * "reduce" to the symbol on the left hand side. When the parser sees
 * the sequence of symbols on the right where it "wants" to see a
 * nonterminal on the left, the rule fires, executing the semantic
 * action code in curly {} braces as it reduces the right hand side to
 * the left hand side.
 *
 * The semantic action code for a rule produces an output, which it
 * can reference using the $$ token. The set of possible types
 * returned in output expressions is given in the %union section of
 * the .y file. The specific type of the output for a terminal or
 * nonterminal symbol (corresponding to a field in the %union) is
 * given by the %type directive in the .y file. The action code can
 * access the outputs of the symbols on the right hand side by using
 * the notation $1 for the first symbol, $2 for the second symbol, and
 * so on.
 *
 * The lexer (generated by flex from lexer.l) feeds a stream of
 * terminal symbols up to this parser. Parser semantic actions can
 * access the lexer output for a terminal symbol with the same
 * notation they use for nonterminals.
 *
 */

/* The first part of the .y file consists of C code that bison copies
 * directly into the top of the .c file it generates.
 */

#if !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "inet/common/INETDefs.h"

#if !defined(_WIN32) && !defined(__WIN32__) && !defined(WIN32) && !defined(__CYGWIN__) && !defined(_WIN64)
#include <arpa/inet.h>
#include <netinet/in.h>
#else
#include "winsock2.h"
#endif
#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "PacketDrillUtils.h"
#include "PacketDrill.h"


/* This include of the bison-generated .h file must go last so that we
 * can first include all of the declarations on which it depends.
 */
#include "parser.h"

/* Change this YYDEBUG to 1 to get verbose debug output for parsing: */
#define YYDEBUG 0
#if YYDEBUG
extern int yydebug;
#endif

extern FILE *yyin;
extern int yylineno;
extern int yywrap(void);
extern char *yytext;
extern int yylex(void);
extern int yyparse(void);

/* The input to the parser: the path name of the script file to parse. */
static const char* current_script_path = NULL;

/* The starting line number of the input script statement that we're
 * currently parsing. This may be different than yylineno if bison had
 * to look ahead and lexically scan a token on the following line to
 * decide that the current statement is done.
 */
static int current_script_line = -1;

/*
 * We use this object to look up configuration info needed during
 * parsing.
 */
static PacketDrillConfig *in_config = NULL;

/* The output of the parser: an output script containing
 * 1) a linked list of options
 * 2) a linked list of events
 */
static PacketDrillScript *out_script = NULL;


/* The test invocation to pass back to parse_and_finalize_config(). */
struct invocation *invocation;

/* This standard callback is invoked by flex when it encounters
 * the end of a file. We return 1 to tell flex to return EOF.
 */
int yywrap(void)
{
    return 1;
}


/* The public entry point for the script parser. Parses the
 * text script file with the given path name and fills in the script
 * object with the parsed representation.
 */
int parse_script(PacketDrillConfig *config, PacketDrillScript *script, struct invocation *callback_invocation){
    /* This bison-generated parser is not multi-thread safe, so we
     * have a lock to prevent more than one thread using the
     * parser at the same time. This is useful in the wire server
     * context, where in general we may have more than one test
     * thread running at the same time.
     */

#if YYDEBUG
    yydebug = 1;
#endif

    /* Now parse the script from our buffer. */
    yyin = fopen(script->getScriptPath(), "r");
    if (!yyin)
        printf("fopen: parse error opening script buffer");
    current_script_path = config->getScriptPath();
    in_config = config;
    out_script = script;
    invocation = callback_invocation;

    /* We have to reset the line number here since the wire server
     * can do more than one yyparse().
     */
    yylineno = 1;
    int result = yyparse(); /* invoke bison-generated parser */
    current_script_path = NULL;
    if (fclose(yyin))
        printf("fclose: error closing script buffer");

    /* Unlock parser. */

    return result ? -1 : 0;
}

/* Bison emits code to call this method when there's a parse-time error.
 * We print the line number and the error message.
 */
static void yyerror(const char *message) {
    fprintf(stderr, "%s:%d: parse error at '%s': %s\n",
        current_script_path, yylineno, yytext, message);
}


/* Create and initalize a new integer expression with the given
 * literal value and format string.
 */
static PacketDrillExpression *new_integer_expression(int64 num, const char *format) {
    PacketDrillExpression *expression = new PacketDrillExpression(EXPR_INTEGER);
    expression->setNum(num);
    expression->setFormat(format);
    return expression;
}


/* Create and initialize a new option. */
/*static struct option_list *new_option(char *name, char *value)
{
    return NULL;
}*/

%}

%locations
%expect 1  /* we expect a shift/reduce conflict for the | binary expression */
/* The %union section specifies the set of possible types for values
 * for all nonterminal and terminal symbols in the grammar.
 */
%union {
    int64 integer;
    double floating;
    char *string;
    char *reserved;
    int64 time_usecs;
    enum direction_t direction;
    uint16 port;
    int32 window;
    uint32 sequence_number;
    struct {
        int protocol;    /* IPPROTO_TCP or IPPROTO_UDP */
        uint32 start_sequence;
        uint16 payload_bytes;
    } tcp_sequence_info;
    struct option_list *option;
    PacketDrillEvent *event;
    PacketDrillPacket *packet;
    struct syscall_spec *syscall;
    PacketDrillStruct *sack_block;
    PacketDrillExpression *expression;
    cQueue *expression_list;
    PacketDrillTcpOption *tcp_option;
    PacketDrillSctpParameter *sctp_parameter;
    cQueue *tcp_options;
    struct errno_spec *errno_info;
    cQueue *sctp_chunk_list;
    cQueue *sctp_parameter_list;
    cQueue *sack_block_list;
    PacketDrillBytes *byte_list;
    uint8 byte;
    PacketDrillSctpChunk *sctp_chunk;
}

/* The specific type of the output for a symbol is given by the %type
 * directive. By convention terminal symbols returned from the lexer
 * have ALL_CAPS names, and nonterminal symbols have lower_case names.
 */
%token ELLIPSIS
%token <reserved> UDP
%token <reserved> ACK WIN WSCALE MSS NOP TIMESTAMP ECR EOL TCPSACK VAL SACKOK
%token <reserved> OPTION
%token <reserved> CHUNK MYDATA MYINIT MYINIT_ACK MYHEARTBEAT MYHEARTBEAT_ACK MYABORT
%token <reserved> MYSHUTDOWN MYSHUTDOWN_ACK MYERROR MYCOOKIE_ECHO MYCOOKIE_ACK
%token <reserved> MYSHUTDOWN_COMPLETE
%token <reserved> HEARTBEAT_INFORMATION CAUSE_INFO MYSACK STATE_COOKIE PARAMETER MYSCTP
%token <reserved> TYPE FLAGS LEN
%token <reserved> TAG A_RWND OS IS TSN SID SSN PPID CUM_TSN GAPS DUPS
%token <floating> MYFLOAT
%token <integer> INTEGER HEX_INTEGER
%token <string> MYWORD MYSTRING
%type <direction> direction
%type <event> event events event_time action
%type <time_usecs> time opt_end_time
%type <packet> packet_spec tcp_packet_spec udp_packet_spec sctp_packet_spec
%type <packet> packet_prefix
%type <syscall> syscall_spec
%type <string> flags
%type <tcp_sequence_info> seq
%type <tcp_options> opt_tcp_options tcp_option_list
%type <tcp_option> tcp_option
%type <string> opt_note note word_list
%type <sack_block> sack_block gap dup
%type <window> opt_window
%type <sequence_number> opt_ack
%type <string> script
%type <string> function_name
%type <sack_block_list> sack_block_list opt_gaps gap_list dup_list opt_dups
%type <expression_list> expression_list function_arguments
%type <expression_list> opt_parameter_list sctp_parameter_list
%type <expression> expression binary_expression array
%type <expression> decimal_integer hex_integer
%type <errno_info> opt_errno
%type <integer> opt_flags opt_len opt_data_flags opt_abort_flags
%type <integer> opt_shutdown_complete_flags opt_tag opt_a_rwnd opt_os opt_is
%type <integer> opt_tsn opt_sid opt_ssn opt_ppid opt_cum_tsn
%type <sctp_chunk_list> sctp_chunk_list
%type <sctp_chunk> sctp_chunk
%type <sctp_chunk> sctp_data_chunk_spec sctp_abort_chunk_spec
%type <sctp_chunk> sctp_init_chunk_spec sctp_init_ack_chunk_spec
%type <sctp_chunk> sctp_sack_chunk_spec sctp_heartbeat_chunk_spec sctp_heartbeat_ack_chunk_spec
%type <sctp_chunk> sctp_shutdown_chunk_spec sctp_shutdown_ack_chunk_spec
%type <sctp_chunk> sctp_cookie_echo_chunk_spec sctp_cookie_ack_chunk_spec
%type <sctp_chunk> sctp_shutdown_complete_chunk_spec
%type <sctp_parameter> sctp_parameter sctp_heartbeat_information_parameter
%type <sctp_parameter> sctp_state_cookie_parameter
%type <byte_list> opt_val byte_list
%type <byte> byte;

%%  /* The grammar follows. */

script
: events {
    $$ = NULL;    /* The parser output is in out_script */
}
;


events
: event {
    out_script->addEvent($1);    /* save pointer to event list as output of parser */
    $$ = $1;    /* return the tail so that we can append to it */
}
| events event {
    out_script->addEvent($2);
    $$ = $2;    /* return the tail so that we can append to it */
}
;

event
: event_time action {
    $$ = $2;
    $$->setLineNumber($1->getLineNumber());    /* use timestamp's line */
    $$->setEventTime($1->getEventTime());
    $$->setEventTimeEnd($1->getEventTimeEnd());
    $$->setTimeType($1->getTimeType());
    $1->getLineNumber(),
    $1->getEventTime().dbl(),
    $1->getEventTimeEnd().dbl(),
    $1->getTimeType();
    if ($$->getEventTimeEnd() != NO_TIME_RANGE) {
        if ($$->getEventTimeEnd() < $$->getEventTime())
            printf("Semantic error: time range is backwards");
    }
    if ($$->getTimeType() == ANY_TIME &&  ($$->getType() != PACKET_EVENT ||
        ($$->getPacket())->getDirection() != DIRECTION_OUTBOUND)) {
        yylineno = $$->getLineNumber();
        printf("Semantic error: event time <star> can only be used with outbound packets");
    } else if (($$->getTimeType() == ABSOLUTE_RANGE_TIME ||
        $$->getTimeType() == RELATIVE_RANGE_TIME) &&
        ($$->getType() != PACKET_EVENT ||
        ($$->getPacket())->getDirection() != DIRECTION_OUTBOUND)) {
        yylineno = $$->getLineNumber();
        printf("Semantic error: event time range can only be used with outbound packets");
    }
    free($1);
}
;

event_time
: '+' time {
    $$ = new PacketDrillEvent(INVALID_EVENT);
    $$->setLineNumber(@2.first_line);
    $$->setEventTime($2);
    $$->setTimeType(RELATIVE_TIME);
}
| time {
    $$ = new PacketDrillEvent(INVALID_EVENT);
    $$->setLineNumber(@1.first_line);
    $$->setEventTime($1);
    $$->setTimeType(ABSOLUTE_TIME);
}
| '*' {
    $$ = new PacketDrillEvent(INVALID_EVENT);
    $$->setLineNumber(@1.first_line);
    $$->setTimeType(ANY_TIME);
}
| time '~' time {
    $$ = new PacketDrillEvent(INVALID_EVENT);
    $$->setLineNumber(@1.first_line);
    $$->setTimeType(ABSOLUTE_RANGE_TIME);
    $$->setEventTime($1);
    $$->setEventTimeEnd($3);
}
| '+' time '~' '+' time {
    $$ = new PacketDrillEvent(INVALID_EVENT);
    $$->setLineNumber(@1.first_line);
    $$->setTimeType(RELATIVE_RANGE_TIME);
    $$->setEventTime($2);
    $$->setEventTimeEnd($5);
}
;

time
: MYFLOAT {
    if ($1 < 0) {
        printf("Semantic error: negative time");
    }
    $$ = (int64)($1 * 1.0e6); /* convert float secs to s64 microseconds */
}
| INTEGER {
    if ($1 < 0) {
        printf("Semantic error: negative time");
    }
    $$ = (int64)($1 * 1000000); /* convert int secs to s64 microseconds */
}
;

action
: packet_spec {
    $$ = new PacketDrillEvent(PACKET_EVENT);  $$->setPacket($1);
}
| syscall_spec {
    $$ = new PacketDrillEvent(SYSCALL_EVENT);
    $$->setSyscall($1);
}
;

packet_spec
: tcp_packet_spec {
    $$ = $1;
}
| udp_packet_spec {
    $$ = $1;
}
| sctp_packet_spec {
    $$ = $1;
}
;

tcp_packet_spec
: packet_prefix flags seq opt_ack opt_window opt_tcp_options {
    char *error = NULL;
    PacketDrillPacket *outer = $1, *inner = NULL;
    enum direction_t direction = outer->getDirection();

    if (($6 == NULL) && (direction != DIRECTION_OUTBOUND)) {
        yylineno = @6.first_line;
        printf("<...> for TCP options can only be used with outbound packets");
    }
    cPacket* pkt = PacketDrill::buildTCPPacket(in_config->getWireProtocol(), direction,
                                               $2,
                                               $3.start_sequence, $3.payload_bytes,
                                               $4, $5, $6, &error);

    free($2);

    inner = new PacketDrillPacket();
    inner->setInetPacket(pkt);

    inner->setDirection(direction);

    $$ = inner;
}
;

udp_packet_spec
: packet_prefix UDP '(' INTEGER ')' {
    char *error = NULL;
    PacketDrillPacket *outer = $1, *inner = NULL;

    enum direction_t direction = outer->getDirection();

    cPacket* pkt = PacketDrill::buildUDPPacket(in_config->getWireProtocol(), direction, $4, &error);
    if (direction == DIRECTION_INBOUND)
        pkt->setName("parserInbound");
    else
        pkt->setName("parserOutbound");
    inner = new PacketDrillPacket();
    inner->setInetPacket(pkt);
    inner->setDirection(direction);

    $$ = inner;
}
;

sctp_packet_spec
: packet_prefix MYSCTP ':' sctp_chunk_list {
    PacketDrillPacket *outer = $1, *inner = NULL;
    enum direction_t direction = outer->getDirection();
    cPacket* pkt = PacketDrill::buildSCTPPacket(in_config->getWireProtocol(), direction, $4);
    if (direction == DIRECTION_INBOUND)
        pkt->setName("parserInbound");
    else
        pkt->setName("parserOutbound");
    inner = new PacketDrillPacket();
    inner->setInetPacket(pkt);
    inner->setDirection(direction);
    $$ = inner;
}
;

sctp_chunk_list
: sctp_chunk                     { $$ = new cQueue("sctpChunkList");
                                   $$->insert((cObject*)$1); }
| sctp_chunk_list ',' sctp_chunk { $$ = $1;
                                   $1->insert($3); }
;


sctp_chunk
: sctp_data_chunk_spec              { $$ = $1; }
| sctp_init_chunk_spec              { $$ = $1; }
| sctp_init_ack_chunk_spec          { $$ = $1; }
| sctp_sack_chunk_spec              { $$ = $1; }
| sctp_heartbeat_chunk_spec         { $$ = $1; }
| sctp_heartbeat_ack_chunk_spec     { $$ = $1; }
| sctp_abort_chunk_spec             { $$ = $1; }
| sctp_shutdown_chunk_spec          { $$ = $1; }
| sctp_shutdown_ack_chunk_spec      { $$ = $1; }
| sctp_cookie_echo_chunk_spec       { $$ = $1; }
| sctp_cookie_ack_chunk_spec        { $$ = $1; }
| sctp_shutdown_complete_chunk_spec { $$ = $1; }
;


opt_flags
: FLAGS '=' ELLIPSIS    { $$ = -1; }
| FLAGS '=' HEX_INTEGER {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' INTEGER     {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
;

opt_len
: LEN '=' ELLIPSIS { $$ = -1; }
| LEN '=' INTEGER  {
    if (!is_valid_u16($3)) {
        printf("Semantic error: length value out of range");
    }
    $$ = $3;
}
;

opt_val
: VAL '=' ELLIPSIS          { $$ = NULL; }
| VAL '=' '[' ELLIPSIS ']'  { $$ = NULL; }
| VAL '=' '[' byte_list ']' { $$ = $4; }
;

byte_list
: byte               { $$ = new PacketDrillBytes($1); }
| byte_list ',' byte { $$ = $1;
                       $1->appendByte($3); }
;

byte
: HEX_INTEGER {
    if (!is_valid_u8($1)) {
        printf("Semantic error: byte value out of range");
    }
    $$ = $1;
}
| INTEGER {
    if (!is_valid_u8($1)) {
        printf("Semantic error: byte value out of range");
    }
    $$ = $1;
}
;

opt_data_flags
: FLAGS '=' ELLIPSIS    { $$ = -1; }
| FLAGS '=' HEX_INTEGER {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' INTEGER     {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' MYWORD        {
    uint64 flags;
    char *c;

    flags = 0;
    for (c = $3; *c != '\0'; c++) {
        switch (*c) {
        case 'I':
            if (flags & SCTP_DATA_CHUNK_I_BIT) {
                printf("Semantic error: I-bit specified multiple times");
            } else {
                flags |= SCTP_DATA_CHUNK_I_BIT;
            }
            break;
        case 'U':
            if (flags & SCTP_DATA_CHUNK_U_BIT) {
                printf("Semantic error: U-bit specified multiple times");
            } else {
                flags |= SCTP_DATA_CHUNK_U_BIT;
            }
            break;
        case 'B':
            if (flags & SCTP_DATA_CHUNK_B_BIT) {
                printf("Semantic error: B-bit specified multiple times");
            } else {
                flags |= SCTP_DATA_CHUNK_B_BIT;
            }
            break;
        case 'E':
            if (flags & SCTP_DATA_CHUNK_E_BIT) {
                printf("Semantic error: E-bit specified multiple times");
            } else {
                flags |= SCTP_DATA_CHUNK_E_BIT;
            }
            break;
        default:
            printf("Semantic error: Only expecting IUBE as flags");
            break;
        }
    }
    $$ = flags;
}
;

opt_abort_flags
: FLAGS '=' ELLIPSIS    { $$ = -1; }
| FLAGS '=' HEX_INTEGER {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' INTEGER     {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' MYWORD        {
    uint64 flags;
    char *c;

    flags = 0;
    for (c = $3; *c != '\0'; c++) {
        switch (*c) {
        case 'T':
            if (flags & SCTP_ABORT_CHUNK_T_BIT) {
                printf("Semantic error: T-bit specified multiple times");
            } else {
                flags |= SCTP_ABORT_CHUNK_T_BIT;
            }
            break;
        default:
            printf("Semantic error: Only expecting T as flags");
            break;
        }
    }
    $$ = flags;
}
;

opt_shutdown_complete_flags
: FLAGS '=' ELLIPSIS    { $$ = -1; }
| FLAGS '=' HEX_INTEGER {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' INTEGER     {
    if (!is_valid_u8($3)) {
        printf("Semantic error: flags value out of range");
    }
    $$ = $3;
}
| FLAGS '=' MYWORD        {
    uint64 flags;
    char *c;

    flags = 0;
    for (c = $3; *c != '\0'; c++) {
        switch (*c) {
        case 'T':
            if (flags & SCTP_SHUTDOWN_COMPLETE_CHUNK_T_BIT) {
                printf("Semantic error: T-bit specified multiple times");
            } else {
                flags |= SCTP_SHUTDOWN_COMPLETE_CHUNK_T_BIT;
            }
            break;
        default:
            printf("Semantic error: Only expecting T as flags");
            break;
        }
    }
    $$ = flags;
}
;


opt_tag
: TAG '=' ELLIPSIS { $$ = -1; }
| TAG '=' INTEGER  {
    if (!is_valid_u32($3)) {
        printf("Semantic error: tag value out of range");
    }
    $$ = $3;
}
;

opt_a_rwnd
: A_RWND '=' ELLIPSIS   { $$ = -1; }
| A_RWND '=' INTEGER    {
    if (!is_valid_u32($3)) {
        printf("Semantic error: a_rwnd value out of range");
    }
    $$ = $3;
}
;

opt_os
: OS '=' ELLIPSIS { $$ = -1; }
| OS '=' INTEGER  {
    if (!is_valid_u16($3)) {
        printf("Semantic error: os value out of range");
    }
    $$ = $3;
}
;

opt_is
: IS '=' ELLIPSIS { $$ = -1; }
| IS '=' INTEGER  {
    if (!is_valid_u16($3)) {
        printf("Semantic error: is value out of range");
    }
    $$ = $3;
}
;

opt_tsn
: TSN '=' ELLIPSIS { $$ = -1; }
| TSN '=' INTEGER  {
    if (!is_valid_u32($3)) {
        printf("Semantic error: tsn value out of range");
    }
    $$ = $3;
}
;

opt_sid
: SID '=' ELLIPSIS { $$ = -1; }
| SID '=' INTEGER  {
    if (!is_valid_u16($3)) {
        printf("Semantic error: sid value out of range");
    }
    $$ = $3;
}
;

opt_ssn
: SSN '=' ELLIPSIS { $$ = -1; }
| SSN '=' INTEGER  {
    if (!is_valid_u16($3)) {
        printf("Semantic error: ssn value out of range");
    }
    $$ = $3;
}
;


opt_ppid
: PPID '=' ELLIPSIS { $$ = -1; }
| PPID '=' INTEGER  {
    if (!is_valid_u32($3)) {
        printf("Semantic error: ppid value out of range");
    }
    $$ = $3;
}
| PPID '=' HEX_INTEGER  {
    if (!is_valid_u32($3)) {
        printf("Semantic error: ppid value out of range");
    }
    $$ = $3;
}
;

opt_cum_tsn
: CUM_TSN '=' ELLIPSIS { $$ = -1; }
| CUM_TSN '=' INTEGER  {
    if (!is_valid_u32($3)) {
        printf("Semantic error: cum_tsn value out of range");
    }
    $$ = $3;
}
;

opt_gaps
: GAPS '=' ELLIPSIS         { $$ = NULL; }
| GAPS '=' '[' ELLIPSIS ']' { $$ = NULL; }
| GAPS '=' '[' gap_list ']' { $$ = $4; }
;


opt_dups
: DUPS '=' ELLIPSIS         { $$ = NULL; }
| DUPS '=' '[' ELLIPSIS ']' { $$ = NULL; }
| DUPS '=' '[' dup_list ']' { $$ = $4; }
;


sctp_data_chunk_spec
: MYDATA '[' opt_data_flags ',' opt_len ',' opt_tsn ',' opt_sid ',' opt_ssn ',' opt_ppid ']' {
    if (($5 != -1) &&
        (!is_valid_u16($5) || ($5 < SCTP_DATA_CHUNK_LENGTH))) {
        printf("Semantic error: length value out of range");
    }
    $$ = PacketDrill::buildDataChunk($3, $5, $7, $9, $11, $13);
}

sctp_init_chunk_spec
: MYINIT '[' opt_flags ',' opt_tag ',' opt_a_rwnd ',' opt_os ',' opt_is ',' opt_tsn opt_parameter_list ']' {
    $$ = PacketDrill::buildInitChunk($3, $5, $7, $9, $11, $13, $14);
}

sctp_init_ack_chunk_spec
: MYINIT_ACK '[' opt_flags ',' opt_tag ',' opt_a_rwnd ',' opt_os ',' opt_is ',' opt_tsn opt_parameter_list ']' {
    $$ = PacketDrill::buildInitAckChunk($3, $5, $7, $9, $11, $13, $14);
}

sctp_sack_chunk_spec
: MYSACK '[' opt_flags ',' opt_cum_tsn ',' opt_a_rwnd ',' opt_gaps ',' opt_dups']' {
    $$ = PacketDrill::buildSackChunk($3, $5, $7, $9, $11);
}

sctp_heartbeat_chunk_spec
: MYHEARTBEAT '[' opt_flags ',' sctp_heartbeat_information_parameter ']' {
    $$ = PacketDrill::buildHeartbeatChunk($3, $5);
}


sctp_heartbeat_ack_chunk_spec
: MYHEARTBEAT_ACK '[' opt_flags ',' sctp_heartbeat_information_parameter ']' {
    $$ = PacketDrill::buildHeartbeatAckChunk($3, $5);
}


sctp_abort_chunk_spec
: MYABORT '[' opt_abort_flags ']' {
    $$ = PacketDrill::buildAbortChunk($3);
}

sctp_shutdown_chunk_spec
: MYSHUTDOWN '[' opt_flags ',' opt_cum_tsn ']' {
    $$ = PacketDrill::buildShutdownChunk($3, $5);
}

sctp_shutdown_ack_chunk_spec
: MYSHUTDOWN_ACK '[' opt_flags ']' {
    $$ = PacketDrill::buildShutdownAckChunk($3);
}

sctp_cookie_echo_chunk_spec
: MYCOOKIE_ECHO '[' opt_flags ',' opt_len ',' opt_val ']' {
    if (($5 != -1) &&
        (!is_valid_u16($5) || ($5 < SCTP_COOKIE_ACK_LENGTH))) {
        printf("Semantic error: length value out of range");
    }
    if (($5 != -1) && ($7 != NULL) &&
        ($5 != SCTP_COOKIE_ACK_LENGTH + $7->getListLength())) {
        printf("Semantic error: length value incompatible with val");
    }
    if (($5 == -1) && ($7 != NULL)) {
        printf("Semantic error: length needs to be specified");
    }
    $$ = PacketDrill::buildCookieEchoChunk($3, $5, $7);
}

sctp_cookie_ack_chunk_spec
: MYCOOKIE_ACK '[' opt_flags ']' {
    $$ = PacketDrill::buildCookieAckChunk($3);
}

sctp_shutdown_complete_chunk_spec
: MYSHUTDOWN_COMPLETE '[' opt_shutdown_complete_flags ']' {
    $$ = PacketDrill::buildShutdownCompleteChunk($3);
}

opt_parameter_list
: ',' ELLIPSIS                 { $$ = NULL; }
| ',' sctp_parameter_list { $$ = $2; }
;

sctp_parameter_list
: sctp_parameter {
    $$ = new cQueue("sctp_parameter_list");
    $$->insert($1);
}
| sctp_parameter_list ',' sctp_parameter {
    $$ = $1;
    $$->insert($3);
}
;


sctp_parameter
: sctp_heartbeat_information_parameter   { $$ = $1; }
| sctp_state_cookie_parameter            { $$ = $1; }
;


sctp_heartbeat_information_parameter
: HEARTBEAT_INFORMATION '[' ELLIPSIS ']' {
    $$ = new PacketDrillSctpParameter(-1, NULL);
}
| HEARTBEAT_INFORMATION '[' opt_len ',' opt_val ']' {
    if (($3 != -1) &&
        (!is_valid_u16($3) || ($3 < 4))) {
        printf("Semantic error: length value out of range");
    }
    if (($3 != -1) && ($5 != NULL) &&
        ($3 != 4 + $5->getListLength())) {
        printf("Semantic error: length value incompatible with val");
    }
    if (($3 == -1) && ($5 != NULL)) {
        printf("Semantic error: length needs to be specified");
    }
    $$ = new PacketDrillSctpParameter($3, $5);
}


sctp_state_cookie_parameter
: STATE_COOKIE '[' ELLIPSIS ']' {
    $$ = new PacketDrillSctpParameter(-1, NULL);
}
| STATE_COOKIE '[' LEN '=' ELLIPSIS ',' VAL '=' ELLIPSIS ']' {
    $$ = new PacketDrillSctpParameter(-1, NULL);
}
| STATE_COOKIE '[' LEN '=' INTEGER ',' VAL '=' ELLIPSIS ']' {
    if (($5 < 4) || !is_valid_u32($5)) {
        printf("Semantic error: len value out of range");
    }
    $$ = new PacketDrillSctpParameter($5, NULL);
}
;


packet_prefix
: direction {
    $$ = new PacketDrillPacket();
    $$->setDirection($1);
}
;


direction
: '<' {
    $$ = DIRECTION_INBOUND;
    current_script_line = yylineno;
}
| '>' {
    $$ = DIRECTION_OUTBOUND;
    current_script_line = yylineno;
}
;

flags
: MYWORD {
    $$ = $1;
}
| '.' {
    $$ = strdup(".");
}
| MYWORD '.' {
#if !defined(_WIN32) && !defined(__WIN32__) && !defined(WIN32) && !defined(__CYGWIN__) && !defined(_WIN64)
    asprintf(&($$), "%s.", $1);
#else
    sprintf(&($$), "%s.", $1);
#endif
    free($1);
}
| '-' {
    $$ = strdup("");
}    /* no TCP flags set in segment */
;

seq
: INTEGER ':' INTEGER '(' INTEGER ')' {
    if (!is_valid_u32($1)) {
        printf("TCP start sequence number out of range");
    }
    if (!is_valid_u32($3)) {
        printf("TCP end sequence number out of range");
    }
    if (!is_valid_u16($5)) {
        printf("TCP payload size out of range");
    }
    if ($3 != ($1 +$5)) {
        printf("inconsistent TCP sequence numbers and payload size");
    }
    $$.start_sequence = $1;
    $$.payload_bytes = $5;
    $$.protocol = IPPROTO_TCP;
}
;

opt_ack
: {
    $$ = 0;
}
| ACK INTEGER {
    if (!is_valid_u32($2)) {
    printf("TCP ack sequence number out of range");
    }
    $$ = $2;
}
;

opt_window
: {
    $$ = -1;
}
| WIN INTEGER {
    if (!is_valid_u16($2)) {
        printf("TCP window value out of range");
    }
    $$ = $2;
}
;

opt_tcp_options
: {
    $$ = new cQueue("opt_tcp_options");
}
| '<' tcp_option_list '>' {
    $$ = $2;
}
| '<' ELLIPSIS '>' {
    $$ = NULL; /* FLAG_OPTIONS_NOCHECK */
}
;


tcp_option_list
: tcp_option {
    $$ = new cQueue("tcp_option");
    $$->insert($1);
}
| tcp_option_list ',' tcp_option {
    $$ = $1;
    $$->insert($3);
}
;


tcp_option
: NOP {
    $$ = new PacketDrillTcpOption(TCPOPT_NOP, 1);
}
| EOL {
    $$ = new PacketDrillTcpOption(TCPOPT_EOL, 1);
}
| MSS INTEGER {
    $$ = new PacketDrillTcpOption(TCPOPT_MAXSEG, TCPOLEN_MAXSEG);
    if (!is_valid_u16($2)) {
        printf("mss value out of range");
    }
    $$->setMss($2);
}
| WSCALE INTEGER {
    $$ = new PacketDrillTcpOption(TCPOPT_WINDOW, TCPOLEN_WINDOW);
    if (!is_valid_u8($2)) {
        printf("window scale shift count out of range");
    }
    $$->setWindowScale($2);
}
| SACKOK {
    $$ = new PacketDrillTcpOption(TCPOPT_SACK_PERMITTED, TCPOLEN_SACK_PERMITTED);
}
| TCPSACK sack_block_list {
    $$ = new PacketDrillTcpOption(TCPOPT_SACK, 2+8*$2->getLength());
    $$->setBlockList($2);
}
| TIMESTAMP VAL INTEGER ECR INTEGER {
    uint32 val, ecr;
    $$ = new PacketDrillTcpOption(TCPOPT_TIMESTAMP, TCPOLEN_TIMESTAMP);
    if (!is_valid_u32($3)) {
        printf("ts val out of range");
    }
    if (!is_valid_u32($5)) {
        printf("ecr val out of range");
    }
    val = $3;
    ecr = $5;
    $$->setVal(val);
    $$->setEcr(ecr);
}
;

sack_block_list
: sack_block {
    $$ = new cQueue("sack_block_list");
    $$->insert($1);
}
| sack_block_list sack_block {
    $$ = $1; $1->insert($2);
}
;

gap_list
:            { $$ = new cQueue("gap_list");}
|  gap {
    $$ = new cQueue("gap_list");
    $$->insert($1);
}
| gap_list ',' gap {
    $$ = $1; $1->insert($3);
}
;

gap
: INTEGER ':' INTEGER {
    if (!is_valid_u16($1)) {
        printf("semantic_error: start value out of range");
    }
    if (!is_valid_u16($3)) {
        printf("semantic_error: end value out of range");
    }
    $$ = new PacketDrillStruct($1, $3);
}
;

dup_list
:            { $$ = new cQueue("dup_list");}
|  dup {
    $$ = new cQueue("dup_list");
    $$->insert($1);
}
| dup_list ',' dup {
    $$ = $1; $1->insert($3);
}
;

dup
: INTEGER ':' INTEGER {
    if (!is_valid_u16($1)) {
        printf("semantic_error: start value out of range");
    }
    if (!is_valid_u16($3)) {
        printf("semantic_error: end value out of range");
    }
    $$ = new PacketDrillStruct($1, $3);
}
;

sack_block
: INTEGER ':' INTEGER {
    if (!is_valid_u32($1)) {
        printf("TCP SACK left sequence number out of range");
    }
    if (!is_valid_u32($3)) {
        printf("TCP SACK right sequence number out of range");
    }
    PacketDrillStruct *block = new PacketDrillStruct($1, $3);
    if (!is_valid_u32($1)) {
        printf("TCP SACK left sequence number out of range");
    }
    if (!is_valid_u32($3)) {
        printf("TCP SACK right sequence number out of range");
    }
    $$ = block;
}
;

syscall_spec
: opt_end_time function_name function_arguments '=' expression opt_errno opt_note {
    $$ = (struct syscall_spec *)calloc(1, sizeof(struct syscall_spec));
    $$->end_usecs = $1;
    $$->name = $2;
    $$->arguments = $3;
    $$->result = $5;
    $$->error = $6;
    $$->note = $7;
}
;

opt_end_time
: {
    $$ = -1;
}
| ELLIPSIS time {
    $$ = $2;
}
;

function_name
: MYWORD {
    $$ = $1;
    current_script_line = yylineno;
}
;

function_arguments
: '(' ')' {
    $$ = NULL;
}
| '(' expression_list ')' {
    $$ = $2;
}
;

expression_list
: expression {
    $$ = new cQueue("expressionList");
    $$->insert((cObject*)$1);
}
| expression_list ',' expression {
    $$ = $1;
    $1->insert($3);
}
;

expression
: ELLIPSIS {
    $$ = new PacketDrillExpression(EXPR_ELLIPSIS);
}
| decimal_integer {
    $$ = $1; }
| hex_integer {
    $$ = $1;
}
| MYWORD {
    $$ = new PacketDrillExpression(EXPR_WORD);
    $$->setString($1);
}
| MYSTRING {
    $$ = new PacketDrillExpression(EXPR_STRING);
    $$->setString($1);
    $$->setFormat("\"%s\"");
}
| MYSTRING ELLIPSIS {
    $$ = new PacketDrillExpression(EXPR_STRING);
    $$->setString($1);
    $$->setFormat("\"%s\"...");
}
| binary_expression {
    $$ = $1;
}
| array {
    $$ = $1;
}
;



decimal_integer
: INTEGER {
    $$ = new_integer_expression($1, "%ld");
}
;

hex_integer
: HEX_INTEGER {
    $$ = new_integer_expression($1, "%#lx");
}
;

binary_expression
: expression '|' expression {    /* bitwise OR */
    $$ = new PacketDrillExpression(EXPR_BINARY);
    struct binary_expression *binary = (struct binary_expression *) malloc(sizeof(struct binary_expression));
    binary->op = strdup("|");
    binary->lhs = $1;
    binary->rhs = $3;
    $$->setBinary(binary);
}
;

array
: '[' ']' {
    $$ = new PacketDrillExpression(EXPR_LIST);
    $$->setList(NULL);
}
| '[' expression_list ']' {
    $$ = new PacketDrillExpression(EXPR_LIST);
    $$->setList($2);
}
;



opt_errno
: {
    $$ = NULL;
}
| MYWORD note {
    $$ = (struct errno_spec*)malloc(sizeof(struct errno_spec));
    $$->errno_macro = $1;
    $$->strerror = $2;
}
;

opt_note
: {
    $$ = NULL;
}
| note {
    $$ = $1;
}
;

note
: '(' word_list ')' {
    $$ = $2;
}
;

word_list
: MYWORD {
    $$ = $1;
}
| word_list MYWORD {
#if !defined(_WIN32) && !defined(__WIN32__) && !defined(WIN32) && !defined(__CYGWIN__) && !defined(_WIN64)
    asprintf(&($$), "%s %s", $1, $2);
#else
    sprintf($$,"%s %s", $1, $2);
#endif
    free($1);
    free($2);
}
;

