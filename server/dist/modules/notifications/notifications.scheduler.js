"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var NotificationsScheduler_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificationsScheduler = void 0;
const common_1 = require("@nestjs/common");
const schedule_1 = require("@nestjs/schedule");
const prisma_service_1 = require("../../prisma/prisma.service");
const fcm_service_1 = require("./fcm.service");
const notifications_service_1 = require("./notifications.service");
let NotificationsScheduler = NotificationsScheduler_1 = class NotificationsScheduler {
    constructor(prisma, fcmService, notificationsService) {
        this.prisma = prisma;
        this.fcmService = fcmService;
        this.notificationsService = notificationsService;
        this.logger = new common_1.Logger(NotificationsScheduler_1.name);
    }
    async handleBirthdayReminders() {
        this.logger.log('🎂 Running daily birthday reminder job...');
        try {
            const now = new Date();
            const upcomingBirthdays = await this.findUpcomingBirthdays(now, 7);
            if (upcomingBirthdays.length === 0) {
                this.logger.log('🎂 No upcoming birthdays found in the next 7 days');
                return;
            }
            this.logger.log(`🎂 Found ${upcomingBirthdays.length} upcoming birthday(s) in the next 7 days`);
            let notificationsSent = 0;
            for (const birthday of upcomingBirthdays) {
                try {
                    const familyMembers = await this.prisma.familyMember.findMany({
                        where: {
                            familyId: birthday.familyId,
                            userId: { not: undefined },
                        },
                        include: {
                            user: {
                                select: {
                                    id: true,
                                    name: true,
                                },
                            },
                        },
                    });
                    if (familyMembers.length === 0) {
                        this.logger.debug(`No family members to notify for ${birthday.name}'s birthday in family ${birthday.familyId}`);
                        continue;
                    }
                    const daysUntil = birthday.daysUntil;
                    const memberName = birthday.name;
                    const title = '🎂 Birthday Reminder';
                    const body = daysUntil === 0
                        ? `It's ${memberName}'s birthday today! 🎉`
                        : `It's ${memberName}'s birthday in ${daysUntil} day${daysUntil !== 1 ? 's' : ''}!`;
                    const family = await this.prisma.family.findUnique({
                        where: { id: birthday.familyId },
                        select: { name: true },
                    });
                    for (const member of familyMembers) {
                        try {
                            const pref = await this.prisma.notificationPreference.findUnique({
                                where: {
                                    userId_eventType: {
                                        userId: member.user.id,
                                        eventType: 'birthday_reminder',
                                    },
                                },
                            });
                            if (pref && !pref.push) {
                                this.logger.debug(`User ${member.user.id} has disabled push for birthday_reminder — skipping FCM`);
                                if (pref.inApp) {
                                    await this.createInAppNotification(member.user.id, birthday, title, body, family?.name);
                                }
                                continue;
                            }
                            if (pref && this.isInQuietHours(pref.quietHoursStart, pref.quietHoursEnd)) {
                                this.logger.debug(`User ${member.user.id} is in quiet hours — skipping push notification`);
                                await this.createInAppNotification(member.user.id, birthday, title, body, family?.name);
                                continue;
                            }
                            const notificationData = {
                                type: 'birthday_reminder',
                                memberId: birthday.id,
                                memberName,
                                familyId: birthday.familyId,
                                daysUntil: String(daysUntil),
                                title,
                                body,
                            };
                            if (family?.name) {
                                notificationData.familyName = family.name;
                            }
                            const fcmSent = await this.fcmService.sendToUser(member.user.id, {
                                title,
                                body,
                                data: notificationData,
                            });
                            await this.createInAppNotification(member.user.id, birthday, title, body, family?.name);
                            if (fcmSent) {
                                notificationsSent++;
                            }
                        }
                        catch (error) {
                            this.logger.error(`Error sending birthday reminder to user ${member.user.id}: ${error?.message}`);
                        }
                    }
                }
                catch (error) {
                    this.logger.error(`Error processing birthday for ${birthday.name}: ${error?.message}`);
                }
            }
            this.logger.log(`🎂 Birthday reminder job complete — sent ${notificationsSent} push notification(s)`);
        }
        catch (error) {
            this.logger.error(`Birthday reminder job failed: ${error?.message}`, error?.stack);
        }
    }
    async findUpcomingBirthdays(now, daysAhead) {
        const persons = await this.prisma.person.findMany({
            where: {
                dateOfBirth: { not: null },
                isDeceased: false,
                deletedAt: null,
            },
            select: {
                id: true,
                name: true,
                familyId: true,
                dateOfBirth: true,
            },
        });
        const results = [];
        for (const person of persons) {
            if (!person.dateOfBirth)
                continue;
            const daysUntil = this.getDaysUntilNextBirthday(person.dateOfBirth, now);
            if (daysUntil >= 0 && daysUntil <= daysAhead) {
                results.push({
                    id: person.id,
                    name: person.name,
                    familyId: person.familyId,
                    dateOfBirth: person.dateOfBirth,
                    daysUntil,
                });
            }
        }
        results.sort((a, b) => a.daysUntil - b.daysUntil);
        return results;
    }
    getDaysUntilNextBirthday(dateOfBirth, now) {
        const birthMonth = dateOfBirth.getMonth();
        const birthDay = dateOfBirth.getDate();
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth();
        const currentDay = now.getDate();
        let nextBirthday = new Date(currentYear, birthMonth, birthDay);
        if (nextBirthday.getMonth() < currentMonth ||
            (nextBirthday.getMonth() === currentMonth && nextBirthday.getDate() < currentDay)) {
            nextBirthday = new Date(currentYear + 1, birthMonth, birthDay);
        }
        const diffMs = nextBirthday.getTime() - new Date(currentYear, currentMonth, currentDay).getTime();
        return Math.round(diffMs / (1000 * 60 * 60 * 24));
    }
    isInQuietHours(quietStart, quietEnd) {
        if (!quietStart || !quietEnd)
            return false;
        try {
            const now = new Date();
            const currentMinutes = now.getHours() * 60 + now.getMinutes();
            const [startH, startM] = quietStart.split(':').map(Number);
            const [endH, endM] = quietEnd.split(':').map(Number);
            const startMinutes = startH * 60 + startM;
            const endMinutes = endH * 60 + endM;
            if (startMinutes <= endMinutes) {
                return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
            }
            else {
                return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
            }
        }
        catch {
            return false;
        }
    }
    async createInAppNotification(userId, birthday, title, body, familyName) {
        try {
            await this.notificationsService.create({
                userId,
                eventType: 'birthday_reminder',
                title,
                body,
                familyId: birthday.familyId,
                personId: birthday.id,
                priority: 'normal',
                actionUrl: `/family/${birthday.familyId}`,
            });
        }
        catch (error) {
            this.logger.error(`Error creating in-app notification for user ${userId}: ${error?.message}`);
        }
    }
};
exports.NotificationsScheduler = NotificationsScheduler;
__decorate([
    (0, schedule_1.Cron)('30 2 * * *', {
        name: 'birthday-reminder',
        timeZone: 'UTC',
    }),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], NotificationsScheduler.prototype, "handleBirthdayReminders", null);
exports.NotificationsScheduler = NotificationsScheduler = NotificationsScheduler_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        fcm_service_1.FcmService,
        notifications_service_1.NotificationsService])
], NotificationsScheduler);
//# sourceMappingURL=notifications.scheduler.js.map