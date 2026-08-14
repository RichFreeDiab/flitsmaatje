# settings.py
# Toggle voor boetemelding (fine notification)
fine_notification_enabled = True

def toggle_fine_notification():
    global fine_notification_enabled
    fine_notification_enabled = not fine_notification_enabled
    return fine_notification_enabled