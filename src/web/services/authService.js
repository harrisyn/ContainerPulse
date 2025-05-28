const bcrypt = require('bcryptjs');

class AuthService {
    constructor() {
        // Default admin user - in production, this should be stored in a database
        this.users = [
            {
                id: 1,
                username: process.env.ADMIN_USERNAME || 'admin',
                passwordHash: this.hashPassword(process.env.ADMIN_PASSWORD || 'admin123'),
                role: 'admin'
            }
        ];
    }

    hashPassword(password) {
        return bcrypt.hashSync(password, 10);
    }

    async authenticate(username, password) {
        try {
            const user = this.users.find(u => u.username === username);
            if (!user) {
                return null;
            }

            const isValidPassword = bcrypt.compareSync(password, user.passwordHash);
            if (!isValidPassword) {
                return null;
            }

            // Return user without password hash
            return {
                id: user.id,
                username: user.username,
                role: user.role
            };
        } catch (error) {
            console.error('Authentication error:', error);
            return null;
        }
    }

    async changePassword(userId, currentPassword, newPassword) {
        try {
            const user = this.users.find(u => u.id === userId);
            if (!user) {
                throw new Error('User not found');
            }

            const isValidPassword = bcrypt.compareSync(currentPassword, user.passwordHash);
            if (!isValidPassword) {
                throw new Error('Current password is incorrect');
            }

            user.passwordHash = this.hashPassword(newPassword);
            return true;
        } catch (error) {
            console.error('Password change error:', error);
            throw error;
        }
    }

    async createUser(username, password, role = 'user') {
        try {
            // Check if user already exists
            const existingUser = this.users.find(u => u.username === username);
            if (existingUser) {
                throw new Error('User already exists');
            }

            const newUser = {
                id: Math.max(...this.users.map(u => u.id)) + 1,
                username,
                passwordHash: this.hashPassword(password),
                role
            };

            this.users.push(newUser);

            return {
                id: newUser.id,
                username: newUser.username,
                role: newUser.role
            };
        } catch (error) {
            console.error('User creation error:', error);
            throw error;
        }
    }

    async deleteUser(userId) {
        try {
            const userIndex = this.users.findIndex(u => u.id === userId);
            if (userIndex === -1) {
                throw new Error('User not found');
            }

            // Prevent deletion of the last admin user
            const adminUsers = this.users.filter(u => u.role === 'admin');
            const userToDelete = this.users[userIndex];
            if (userToDelete.role === 'admin' && adminUsers.length === 1) {
                throw new Error('Cannot delete the last admin user');
            }

            this.users.splice(userIndex, 1);
            return true;
        } catch (error) {
            console.error('User deletion error:', error);
            throw error;
        }
    }

    getUsers() {
        return this.users.map(user => ({
            id: user.id,
            username: user.username,
            role: user.role
        }));
    }
}

module.exports = new AuthService();
