<?php
if (!defined('WP_UNINSTALL_PLUGIN')) { exit; }
delete_metadata('user', 0, 'lightek_connect_token', '', true);
