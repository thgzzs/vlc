/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 VLC authors and VideoLAN
 * Native regression: preparsing must preserve explicit subtitle associations.
 */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#include <vlc_common.h>
#include <vlc_input_item.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static input_item_slave_t *add(input_item_t *item, const char *uri,
                               enum slave_priority priority)
{
    input_item_slave_t *slave = input_item_slave_New(uri, SLAVE_TYPE_SPU, priority);
    assert(slave != NULL);
    assert(input_item_AddSlave(item, slave) == VLC_SUCCESS);
    return slave;
}

int main(void)
{
    input_item_t *item = input_item_New("file:///fixture.avi", "fixture");
    input_item_t *parsed = input_item_New("file:///fixture.avi", "parsed");
    assert(item != NULL && parsed != NULL);
    add(item, "file:///obsolete.srt", SLAVE_PRIORITY_MATCH_ALL);
    add(item, "file:///explicit.srt", SLAVE_PRIORITY_USER)->b_forced = true;
    add(item, "file:///in-flight.srt", SLAVE_PRIORITY_USER);
    add(parsed, "file:///explicit.srt", SLAVE_PRIORITY_MATCH_ALL);
    add(parsed, "file:///detected.srt", SLAVE_PRIORITY_MATCH_ALL);
    for (int repeat = 0; repeat < 3; ++repeat)
    {
        assert(input_item_Update(item, parsed) == VLC_SUCCESS);
        assert(item->i_slaves == 3);
        int explicit_count = 0, in_flight = 0, detected = 0;
        for (int i = 0; i < item->i_slaves; ++i)
        {
            input_item_slave_t *slave = item->pp_slaves[i];
            if (strcmp(slave->psz_uri, "file:///explicit.srt") == 0)
            {
                assert(slave->i_priority == SLAVE_PRIORITY_USER && slave->b_forced);
                ++explicit_count;
            }
            else if (strcmp(slave->psz_uri, "file:///in-flight.srt") == 0)
                ++in_flight;
            else if (strcmp(slave->psz_uri, "file:///detected.srt") == 0)
                ++detected;
            else
                assert(!"Obsolete detected subtitle survived replacement");
        }
        assert(explicit_count == 1 && in_flight == 1 && detected == 1);
    }
    input_item_Release(parsed);
    input_item_Release(item);
    puts("Native input update preserves user subtitles, forced selection and deduplication");
    return 0;
}
