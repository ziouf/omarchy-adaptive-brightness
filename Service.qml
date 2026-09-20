import QtQuick

// The engine lives in the systemd user service (scripts/loop), not here.
// This service entry only marks the plugin as loaded so the shell accepts
// it; UI integration happens in the Display panel clone (see panel/).
Item {}
