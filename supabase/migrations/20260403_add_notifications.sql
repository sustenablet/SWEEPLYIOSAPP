-- Creating the notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auto_profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'system', -- 'schedule', 'billing', 'profile', 'system'
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can fully manage their own notifications"
    ON notifications FOR ALL
    USING (auth.uid() = user_id);

-- Create an index to speed up fetching user notifications
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
