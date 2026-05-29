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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PersonController = exports.PersonsController = void 0;
const common_1 = require("@nestjs/common");
const supabase_auth_guard_1 = require("../auth/supabase-auth.guard");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const persons_service_1 = require("./persons.service");
const add_person_dto_1 = require("../dto/add-person.dto");
const update_person_dto_1 = require("../dto/update-person.dto");
let PersonsController = class PersonsController {
    constructor(personsService) {
        this.personsService = personsService;
    }
    async listPersons(user, familyId) {
        const persons = await this.personsService.listPersons(user.id, familyId);
        return { persons };
    }
    async addPerson(user, familyId, body) {
        const person = await this.personsService.addPerson(user.id, familyId, body);
        return { person };
    }
};
exports.PersonsController = PersonsController;
__decorate([
    (0, common_1.Get)(),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('familyId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], PersonsController.prototype, "listPersons", null);
__decorate([
    (0, common_1.Post)(),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('familyId')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, add_person_dto_1.AddPersonDto]),
    __metadata("design:returntype", Promise)
], PersonsController.prototype, "addPerson", null);
exports.PersonsController = PersonsController = __decorate([
    (0, common_1.Controller)('families/:familyId/persons'),
    __metadata("design:paramtypes", [persons_service_1.PersonsService])
], PersonsController);
let PersonController = class PersonController {
    constructor(personsService) {
        this.personsService = personsService;
    }
    async updatePerson(user, id, body) {
        const person = await this.personsService.updatePerson(user.id, id, body);
        return { person };
    }
    async deletePerson(user, id) {
        return this.personsService.deletePerson(user.id, id);
    }
};
exports.PersonController = PersonController;
__decorate([
    (0, common_1.Patch)(':id'),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, update_person_dto_1.UpdatePersonDto]),
    __metadata("design:returntype", Promise)
], PersonController.prototype, "updatePerson", null);
__decorate([
    (0, common_1.Delete)(':id'),
    (0, common_1.UseGuards)(supabase_auth_guard_1.SupabaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], PersonController.prototype, "deletePerson", null);
exports.PersonController = PersonController = __decorate([
    (0, common_1.Controller)('persons'),
    __metadata("design:paramtypes", [persons_service_1.PersonsService])
], PersonController);
//# sourceMappingURL=persons.controller.js.map