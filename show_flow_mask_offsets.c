#include <stdio.h>
#include "openvswitch/match.h"
#include "openvswitch/types.h"


int main()
{
    struct flow mask;
    int mask_size = sizeof(mask);

    printf("flow mask size: %d\n", mask_size);

    printf("pkt_mark     %d\n", OBJECT_OFFSETOF(&mask, pkt_mark));
    printf("dp_hash      %d\n", OBJECT_OFFSETOF(&mask, dp_hash));
    printf("recirc_id    %d\n", OBJECT_OFFSETOF(&mask, recirc_id));
    printf("packet_type  %d\n", OBJECT_OFFSETOF(&mask, packet_type));
    printf("dl_type      %d\n", OBJECT_OFFSETOF(&mask, dl_type));
    printf("nw_src       %d\n", OBJECT_OFFSETOF(&mask, nw_src));
    printf("nw_frag      %d\n", OBJECT_OFFSETOF(&mask, nw_frag));
    printf("tp_src       %d\n", OBJECT_OFFSETOF(&mask, tp_src));
    printf("tp_dst       %d\n", OBJECT_OFFSETOF(&mask, tp_dst));

    return 0;
}
