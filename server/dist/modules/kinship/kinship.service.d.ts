export interface KinshipTranslation {
    native: string;
    latin: string;
}
export interface KinshipTerm {
    relationshipKey: string;
    englishTerm: string;
    gender: 'male' | 'female' | 'neutral';
    lineage: 'paternal' | 'maternal' | 'neutral';
    relationshipCategory: string;
    translations: Record<string, KinshipTranslation>;
    aliases?: string[];
}
export declare class KinshipService {
    private readonly kinshipTerms;
    constructor();
    lookup(params: {
        key?: string;
        search?: string;
        category?: string;
        gender?: string;
        lineage?: string;
    }): KinshipTerm[];
    getByKey(key: string): KinshipTerm | undefined;
    search(query: string): KinshipTerm[];
    searchByTermAndLang(term: string, lang: string, limit: number): KinshipTerm[];
    getSupportedLanguages(): Array<{
        code: string;
        name: string;
    }>;
    getCategories(): string[];
    getByCategory(category: string): KinshipTerm[];
    getRandomTerms(count: number, category?: string): KinshipTerm[];
    findByNativeTerm(text: string): Array<KinshipTerm & {
        confidence: number;
    }>;
    getAllTerms(): KinshipTerm[];
}
