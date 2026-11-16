import XCTest
@testable import HealthCompanion

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

private func label(
    basis: NutrientBasis = .per100g,
    values: [Nutrient: Double] = [.totalSugars: 24, .protein: 10, .energy: 450],
    serving: Quantity? = Quantity(value: 45, unit: .gram),
    ingredients: String? = "Oats, sugar, almonds.",
    precautionary: PrecautionaryRecord = .noneOnPackage
) -> ConfirmedLabel {
    var stored: [String: NutrientValue] = [:]
    for (nutrient, amount) in values {
        stored[nutrient.rawValue] = NutrientValue(amount: amount, unit: nutrient.defaultUnit)
    }
    return ConfirmedLabel(productName: "Test", isSample: true, rawText: "", basis: basis, values: stored,
                          serving: serving, package: nil, ingredients: ingredients,
                          precautionary: precautionary, confirmedAt: fixedDate)
}

private func profile(_ goals: [Goal] = [.reduceSugar], allergies: AllergyRecord = .notProvided) -> Profile {
    Profile(goals: goals, dietaryPreferences: [], allergies: allergies, consentVersion: 1, updatedAt: fixedDate)
}

final class ParsingTests: XCTestCase {
    func testBlankIsUnknownAndZeroIsZero() {
        XCTAssertEqual(DecimalParsing.parse(""), .unknown)
        XCTAssertEqual(DecimalParsing.parse("   "), .unknown)
        XCTAssertEqual(DecimalParsing.parse("0"), .value(0))
    }

    func testDecimalCommaAndInvalidText() {
        XCTAssertEqual(DecimalParsing.parse("12,5"), .value(12.5))
        XCTAssertEqual(DecimalParsing.parse("3.0"), .value(3))
        XCTAssertEqual(DecimalParsing.parse("abc"), .invalid)
        XCTAssertEqual(DecimalParsing.parse("-2"), .invalid)
        XCTAssertEqual(DecimalParsing.parse("1.2.3"), .invalid)
    }

    func testDraftKeepsUnknownSeparateFromZero() throws {
        var draft = SampleProducts.yoghurtDrink
        draft.checkedNutrition = true
        draft.checkedIngredients = true
        let confirmed = try XCTUnwrap(draft.confirmed(now: fixedDate))
        XCTAssertEqual(confirmed.value(.addedSugars)?.amount, 0, "A stated zero is a real value")
        XCTAssertNil(confirmed.value(.fibre), "A blank field stays unknown")
        XCTAssertNil(confirmed.value(.saturatedFat))
    }

    func testDraftNeedsBasisAndConfirmation() {
        var draft = SampleProducts.granola
        XCTAssertNil(draft.confirmed(), "Unconfirmed drafts cannot be assessed")
        draft.checkedNutrition = true
        draft.checkedIngredients = true
        XCTAssertNotNil(draft.confirmed())
        draft.basis = nil
        XCTAssertNil(draft.confirmed(), "The nutrient basis is required")
        XCTAssertTrue(draft.issues.contains { $0.contains("per 100 g") })
    }

    func testEveryFieldCanBeCorrectedAndBasisChanged() throws {
        var draft = SampleProducts.granola
        draft.checkedNutrition = true
        draft.checkedIngredients = true
        draft.basis = .perServing
        draft[.totalSugars].text = "9,5"
        draft[.salt].unit = .mg
        draft[.energy].unit = .kJ
        draft.servingText = ""
        let confirmed = try XCTUnwrap(draft.confirmed(now: fixedDate))
        XCTAssertEqual(confirmed.basis, .perServing)
        XCTAssertEqual(confirmed.value(.totalSugars)?.amount, 9.5)
        XCTAssertEqual(confirmed.value(.salt)?.unit, .mg)
        XCTAssertEqual(confirmed.value(.energy)?.unit, .kJ)
        XCTAssertNil(confirmed.serving)
    }
}

final class ArithmeticTests: XCTestCase {
    private func factor(_ basis: NutrientBasis, _ serving: Quantity?, _ portion: Portion) -> Result<Double, PortionBlock> {
        NutrientMath.factor(basis: basis, serving: serving, portion: portion)
    }

    func testGramPortionOnPer100g() throws {
        XCTAssertEqual(try factor(.per100g, nil, .amount(Quantity(value: 30, unit: .gram))).get(), 0.3, accuracy: 1e-9)
    }

    func testServingsOnPer100gUseServingMass() throws {
        let serving = Quantity(value: 40, unit: .gram)
        XCTAssertEqual(try factor(.per100g, serving, .servings(1.5)).get(), 0.6, accuracy: 1e-9)
    }

    func testMassAndVolumeAreNeverConverted() {
        XCTAssertEqual(factor(.per100g, nil, .amount(Quantity(value: 30, unit: .millilitre))), .failure(.massVolumeMismatch))
        XCTAssertEqual(factor(.per100ml, nil, .amount(Quantity(value: 30, unit: .gram))), .failure(.massVolumeMismatch))
        XCTAssertEqual(factor(.per100g, Quantity(value: 250, unit: .millilitre), .servings(1)), .failure(.massVolumeMismatch))
        XCTAssertEqual(factor(.perServing, Quantity(value: 250, unit: .millilitre), .amount(Quantity(value: 30, unit: .gram))), .failure(.massVolumeMismatch))
    }

    func testPerServingCannotBeScaledToGramsWithoutServingMass() {
        XCTAssertEqual(factor(.perServing, nil, .amount(Quantity(value: 30, unit: .gram))), .failure(.servingSizeUnknown))
        XCTAssertEqual(factor(.per100g, nil, .servings(1)), .failure(.servingSizeUnknown))
    }

    func testPerServingScalesByServingsAndKnownMass() throws {
        XCTAssertEqual(try factor(.perServing, nil, .servings(2)).get(), 2, accuracy: 1e-9)
        XCTAssertEqual(try factor(.perServing, Quantity(value: 50, unit: .gram), .amount(Quantity(value: 25, unit: .gram))).get(), 0.5, accuracy: 1e-9)
    }

    func testInvalidAmountsAreBlocked() {
        XCTAssertEqual(factor(.perServing, nil, .servings(0)), .failure(.invalidAmount))
        XCTAssertEqual(factor(.per100g, nil, .amount(Quantity(value: -5, unit: .gram))), .failure(.invalidAmount))
    }

    func testChangingPortionUpdatesValuesAndUnknownStaysUnknown() throws {
        let item = label()
        let small = NutrientMath.calculate(label: item, portion: .amount(Quantity(value: 50, unit: .gram)))
        let large = NutrientMath.calculate(label: item, portion: .servings(2))
        XCTAssertEqual(try XCTUnwrap(small.value(.totalSugars)).amount, 12, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(large.value(.totalSugars)).amount, 21.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(large.value(.energy)).amount, 405, accuracy: 1e-9)
        XCTAssertNil(small.value(.addedSugars), "Unknown never becomes zero")
        XCTAssertNil(small.value(.fibre))
    }

    func testBlockedCalculationShowsNoNumbers() {
        let item = label(basis: .perServing, serving: nil)
        let result = NutrientMath.calculate(label: item, portion: .amount(Quantity(value: 30, unit: .gram)))
        XCTAssertEqual(result.blocked, .servingSizeUnknown)
        XCTAssertTrue(result.values.isEmpty)
    }
}

final class AssessmentTests: XCTestCase {
    func testTotalSugarsAreNeverPresentedAsAddedSugars() {
        let result = AssessmentEngine.assess(label: label(), profile: profile([.reduceSugar]), portion: .servings(1), now: fixedDate)
        let added = result.facts.first { $0.nutrient == .addedSugars }
        XCTAssertNil(added?.labelValue)
        XCTAssertNil(added?.portionValue)
        XCTAssertTrue(result.summary.contains { $0.contains("does not state added sugars") })
        XCTAssertFalse(result.summary.contains { $0.hasPrefix("Added sugars:") })
        XCTAssertTrue(result.missing.contains { $0.contains("Added sugars") && $0.contains("unknown, not zero") })
    }

    func testStatedAddedSugarsAreShownSeparately() {
        let item = label(values: [.totalSugars: 4.8, .addedSugars: 0])
        let result = AssessmentEngine.assess(label: item, profile: profile([.reduceSugar]), portion: .servings(1), now: fixedDate)
        XCTAssertTrue(result.summary.contains { $0.hasPrefix("Added sugars: 0 g") })
        XCTAssertTrue(result.summary.contains { $0.hasPrefix("Total sugars: 4.8 g") })
    }

    func testDraftCardsNeverBackARecommendation() {
        for goal in Goal.allCases {
            let result = AssessmentEngine.assess(label: label(), profile: profile([goal]), portion: .servings(1), now: fixedDate)
            XCTAssertNil(result.nextStep.evidenceCardID)
            XCTAssertEqual(result.guidanceNote, AssessmentEngine.noGuidanceNote)
        }
    }

    func testOnlyReviewedApplicableUnexpiredCardsAreEligible() {
        var card = EvidenceCard(id: "c", goal: .reduceSugar, claim: "Claim", population: "Adults", exclusions: "",
                                sources: [], reviewer: "Reviewer", state: .reviewed, version: "1.0",
                                reviewedOn: fixedDate, expiresOn: fixedDate.addingTimeInterval(86_400))
        XCTAssertTrue(card.isEligible(for: .reduceSugar, on: fixedDate))
        XCTAssertFalse(card.isEligible(for: .buildMuscle, on: fixedDate), "Wrong goal")
        XCTAssertFalse(card.isEligible(for: .reduceSugar, on: fixedDate.addingTimeInterval(2 * 86_400)), "Expired")
        card.state = .draft
        XCTAssertFalse(card.isEligible(for: .reduceSugar, on: fixedDate), "Draft")
        card.state = .reviewed
        card.reviewer = nil
        XCTAssertFalse(card.isEligible(for: .reduceSugar, on: fixedDate), "No reviewer")

        card.reviewer = "Reviewer"
        let result = AssessmentEngine.assess(label: label(), profile: profile([.reduceSugar]), portion: .servings(1),
                                             library: [card], now: fixedDate)
        XCTAssertEqual(result.nextStep.evidenceCardID, "c")
    }

    func testBlockedPortionIsExplained() {
        let item = label(basis: .perServing, serving: nil)
        let result = AssessmentEngine.assess(label: item, profile: profile([.buildMuscle]),
                                             portion: .amount(Quantity(value: 30, unit: .gram)), now: fixedDate)
        XCTAssertEqual(result.calculation.blocked, .servingSizeUnknown)
        XCTAssertTrue(result.facts.allSatisfy { $0.portionValue == nil })
        XCTAssertTrue(result.nextStep.text.contains("serving size"))
    }
}

final class AllergenTests: XCTestCase {
    private let nutAllergy = AllergyRecord.confirmed([.treeNuts, .peanuts])

    private func allText(_ result: AllergenCheckResult) -> String {
        ([result.headline, result.detail] + result.gaps).joined(separator: " ").lowercased()
    }

    func testMatchInIngredientsWarns() {
        let result = AllergenCheck.check(label: label(), allergies: nutAllergy)
        XCTAssertEqual(result.status, .matchFound)
        XCTAssertTrue(result.matches.contains { $0.allergen == .treeNuts && $0.term == "almond" })
    }

    func testMatchInPrecautionaryStatementWarns() {
        let item = label(ingredients: "Oats, sugar.", precautionary: .statement("May contain peanuts."))
        let result = AllergenCheck.check(label: item, allergies: nutAllergy)
        XCTAssertEqual(result.status, .matchFound)
        XCTAssertTrue(result.matches.contains { $0.allergen == .peanuts && $0.source == .precautionary })
    }

    func testNoMatchIsNeverAnAllClear() {
        let item = label(ingredients: "Oats, sugar, coconut, nutmeg.")
        let result = AllergenCheck.check(label: item, allergies: nutAllergy)
        XCTAssertEqual(result.status, .noMatchFound)
        XCTAssertTrue(result.detail.contains("not an all-clear"))
        XCTAssertFalse(allText(result).contains("safe"))
        XCTAssertFalse(allText(result).contains("free from"))
    }

    func testMissingInputsStayVisiblyIncomplete() {
        let noIngredients = AllergenCheck.check(label: label(ingredients: nil), allergies: nutAllergy)
        XCTAssertEqual(noIngredients.status, .incomplete)
        XCTAssertFalse(noIngredients.gaps.isEmpty)

        let noStatement = AllergenCheck.check(label: label(ingredients: "Oats.", precautionary: .notProvided), allergies: nutAllergy)
        XCTAssertEqual(noStatement.status, .incomplete)
    }

    func testNoStatusEverSaysSafe() {
        let records: [AllergyRecord] = [.notProvided, .noneReported, nutAllergy, .confirmed([])]
        let labels = [label(), label(ingredients: nil), label(ingredients: "Oats."), label(precautionary: .notProvided)]
        for record in records {
            for item in labels {
                let result = AllergenCheck.check(label: item, allergies: record)
                XCTAssertFalse(allText(result).contains("safe"), result.headline)
            }
        }
    }

    func testNotProvidedAndNoneAreNotChecked() {
        XCTAssertEqual(AllergenCheck.check(label: label(), allergies: .notProvided).status, .notChecked)
        XCTAssertEqual(AllergenCheck.check(label: label(), allergies: .noneReported).status, .notChecked)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    private func makeAssessment(_ store: AppStore) -> Assessment {
        AssessmentEngine.assess(label: label(), profile: store.profile, portion: .servings(1), now: fixedDate)
    }

    func testNothingIsSavedUntilRequested() {
        let persistence = MemoryPersistence()
        let store = AppStore(persistence: persistence)
        store.saveProfile(goals: [.reduceSugar], dietaryPreferences: [], allergies: .notProvided, now: fixedDate)
        let assessment = makeAssessment(store)
        XCTAssertTrue(store.data.assessments.isEmpty)
        XCTAssertTrue(persistence.stored?.assessments.isEmpty ?? false)

        store.saveDecision(assessment: assessment, action: .considering, now: fixedDate)
        XCTAssertEqual(store.data.assessments.count, 1)
        XCTAssertEqual(store.data.decisions.first?.action, .considering)
        XCTAssertEqual(persistence.stored?.decisions.count, 1)
    }

    func testSavedAssessmentSurvivesProfileChange() {
        let store = AppStore(persistence: MemoryPersistence())
        store.saveProfile(goals: [.reduceSugar], dietaryPreferences: [], allergies: .confirmed([.treeNuts]), now: fixedDate)
        let assessment = makeAssessment(store)
        store.saveDecision(assessment: assessment, action: .bought, now: fixedDate)

        store.saveProfile(goals: [.buildMuscle], dietaryPreferences: [.vegan], allergies: .noneReported, now: fixedDate)

        let stored = store.data.assessments[0]
        XCTAssertEqual(stored, assessment)
        XCTAssertEqual(stored.goal, .reduceSugar)
        XCTAssertEqual(stored.allergen.status, .matchFound)
    }

    func testExportReflectsStoredRecords() throws {
        let store = AppStore(persistence: MemoryPersistence())
        store.saveProfile(goals: [.manageWeight, .everydayEnergy], dietaryPreferences: [.vegetarian], allergies: .confirmed([.milk]), now: fixedDate)
        store.saveDecision(assessment: makeAssessment(store), action: .ate, now: fixedDate)
        store.addCheckIn(energy: 4, manageability: 2, note: " felt fine ", now: fixedDate)

        let decoded = try AppCoding.decoder().decode(AppData.self, from: Data(store.exportJSON().utf8))
        XCTAssertEqual(decoded, store.data)
        XCTAssertEqual(decoded.checkIns.first?.note, "felt fine")
    }

    func testEraseRestoresInitialState() {
        let persistence = MemoryPersistence()
        let store = AppStore(persistence: persistence)
        store.saveProfile(goals: [.reduceSugar], dietaryPreferences: [], allergies: .notProvided, now: fixedDate)
        store.saveDecision(assessment: makeAssessment(store), action: .considering, now: fixedDate)
        store.addCheckIn(energy: 3, manageability: 3, note: "", now: fixedDate)

        store.eraseAll()

        XCTAssertEqual(store.data, .empty)
        XCTAssertNil(store.profile)
        XCTAssertNil(persistence.stored)
        XCTAssertEqual(AppStore(persistence: persistence).data, .empty)
    }

    func testFilePersistenceRoundTripAndErase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hc-test-\(UUID().uuidString).json")
        let persistence = FilePersistence(url: url)
        let store = AppStore(persistence: persistence)
        store.saveProfile(goals: [.buildMuscle], dietaryPreferences: [.halal], allergies: .noneReported, now: fixedDate)
        store.saveDecision(assessment: makeAssessment(store), action: .bought, now: fixedDate)

        let reloaded = AppStore(persistence: persistence)
        XCTAssertEqual(reloaded.data, store.data)

        reloaded.eraseAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(try persistence.load())
    }

    func testDeletingDecisionRemovesItsSnapshot() {
        let store = AppStore(persistence: MemoryPersistence())
        let decision = store.saveDecision(assessment: makeAssessment(store), action: .considering, now: fixedDate)
        store.deleteDecision(decision)
        XCTAssertTrue(store.data.decisions.isEmpty)
        XCTAssertTrue(store.data.assessments.isEmpty)
    }

    func testCheckInNeverChangesGoals() {
        let store = AppStore(persistence: MemoryPersistence())
        store.saveProfile(goals: [.reduceSugar, .buildMuscle], dietaryPreferences: [], allergies: .notProvided, now: fixedDate)
        store.addCheckIn(energy: 1, manageability: 1, note: "hard week", now: fixedDate)
        XCTAssertEqual(store.profile?.goals, [.reduceSugar, .buildMuscle])
    }
}

final class LabelTextParserTests: XCTestCase {
    private let european = """
    NUTRITION per 100 g
    Energy 1890 kJ / 450 kcal
    Fat 15 g, of which saturates 3,0 g
    Carbohydrate 62 g, of which sugars 24 g
    Fibre 7 g
    Protein 10 g
    Salt 0,3 g
    Serving 45 g. Net weight 500 g.
    INGREDIENTS: Oats (58%), sugar, sunflower oil, honey (5%),
    almonds (4%), coconut, salt.
    May contain peanuts, other nuts
    and sesame.
    """

    func testEuropeanLabelWithDecimalCommas() {
        let draft = LabelTextParser.parse(european)
        XCTAssertEqual(draft.basis, .per100g)
        XCTAssertEqual(draft[.energy].text, "450")
        XCTAssertEqual(draft[.energy].unit, .kcal)
        XCTAssertEqual(draft[.fat].text, "15")
        XCTAssertEqual(draft[.saturatedFat].text, "3,0")
        XCTAssertEqual(draft[.carbohydrate].text, "62")
        XCTAssertEqual(draft[.totalSugars].text, "24")
        XCTAssertEqual(draft[.fibre].text, "7")
        XCTAssertEqual(draft[.protein].text, "10")
        XCTAssertEqual(draft[.salt].text, "0,3")
        XCTAssertEqual(draft.servingText, "45")
        XCTAssertEqual(draft.servingUnit, .gram)
        XCTAssertEqual(draft.packageText, "500")
        XCTAssertEqual(draft.ingredientsText, "Oats (58%), sugar, sunflower oil, honey (5%), almonds (4%), coconut, salt.")
        XCTAssertEqual(draft.precautionaryMode, .hasStatement)
        XCTAssertEqual(draft.precautionaryText, "May contain peanuts, other nuts and sesame.")
    }

    func testAddedSugarsAreNeverInferred() {
        let draft = LabelTextParser.parse(european)
        XCTAssertEqual(draft[.addedSugars].text, "", "Sugar in the ingredients must not become an added-sugar value")
    }

    func testScannedLabelIsNeverPreConfirmedOrMarkedSample() {
        let draft = LabelTextParser.parse(european)
        XCTAssertFalse(draft.isSample)
        XCTAssertFalse(draft.checkedNutrition)
        XCTAssertFalse(draft.checkedIngredients)
        XCTAssertNil(draft.confirmed())
    }

    func testAmericanStylePerServingLabel() {
        let text = """
        Nutrition Facts
        Serving size 2/3 cup (55g)
        Amount per serving
        Calories 230
        Total Fat 8g
        Saturated Fat 1g
        Trans Fat 0g
        Sodium 160mg
        Total Carbohydrate 37g
        Dietary Fiber 4g
        Total Sugars 12g
        Includes 10g Added Sugars
        Protein 3g
        """
        let draft = LabelTextParser.parse(text)
        XCTAssertEqual(draft.basis, .perServing)
        XCTAssertEqual(draft[.energy].text, "230")
        XCTAssertEqual(draft[.fat].text, "8")
        XCTAssertEqual(draft[.saturatedFat].text, "1")
        XCTAssertEqual(draft[.carbohydrate].text, "37")
        XCTAssertEqual(draft[.fibre].text, "4")
        XCTAssertEqual(draft[.totalSugars].text, "12")
        XCTAssertEqual(draft[.addedSugars].text, "10")
        XCTAssertEqual(draft[.protein].text, "3")
        XCTAssertEqual(draft[.salt].text, "", "Sodium is not salt and is not converted")
        XCTAssertEqual(draft.servingText, "55")
        XCTAssertEqual(draft.precautionaryMode, .notProvided, "No statement found is not the same as none on the package")
    }

    func testValuesOnTheFollowingLineAndPer100ml() {
        let text = """
        Typical values per 100 ml
        Energy
        251 kJ
        Protein
        8.0 g
        Sugars
        4.8 g
        """
        let draft = LabelTextParser.parse(text)
        XCTAssertEqual(draft.basis, .per100ml)
        XCTAssertEqual(draft[.energy].text, "251")
        XCTAssertEqual(draft[.energy].unit, .kJ)
        XCTAssertEqual(draft[.protein].text, "8.0")
        XCTAssertEqual(draft[.totalSugars].text, "4.8")
    }

    func testUnreadableOrLessThanValuesStayBlank() {
        let text = """
        per 100 g
        Fat <0.5 g
        Protein trace
        Salt
        """
        let draft = LabelTextParser.parse(text)
        XCTAssertEqual(draft[.fat].text, "")
        XCTAssertEqual(draft[.protein].text, "")
        XCTAssertEqual(draft[.salt].text, "")
    }

    func testNoBasisIsLeftForTheUserToChoose() {
        let draft = LabelTextParser.parse("Energy 450 kcal\nProtein 10 g")
        XCTAssertNil(draft.basis)
        XCTAssertTrue(draft.issues.contains { $0.contains("per 100 g") })
    }

    func testIngredientsOnlyPhotoYieldsNoNutritionValues() {
        let draft = LabelTextParser.parse("Ingredients: wheat flour, sugar (12%), salt, fat 3 types.")
        for nutrient in Nutrient.allCases {
            XCTAssertEqual(draft[nutrient].text, "", nutrient.title)
        }
        XCTAssertTrue(draft.ingredientsText.hasPrefix("wheat flour"))
    }

    func testSecondPhotoFillsBlanksWithoutOverwritingAndClearsConfirmation() {
        var draft = LabelTextParser.parse("per 100 g\nEnergy 450 kcal\nProtein 10 g")
        draft[.protein].text = "11"
        draft.checkedNutrition = true
        draft.checkedIngredients = true

        LabelTextParser.merge("Protein 99 g\nFibre 7 g\nIngredients: oats, almonds.\nMay contain sesame.", into: &draft)

        XCTAssertEqual(draft[.protein].text, "11", "A correction is never overwritten")
        XCTAssertEqual(draft[.fibre].text, "7")
        XCTAssertEqual(draft.ingredientsText, "oats, almonds.")
        XCTAssertEqual(draft.precautionaryText, "May contain sesame.")
        XCTAssertFalse(draft.checkedNutrition)
        XCTAssertFalse(draft.checkedIngredients)
        XCTAssertTrue(draft.rawText.contains("Protein 99 g"))
    }

    func testPackageSizeInKilogramsAndLitres() {
        XCTAssertEqual(LabelTextParser.package(in: "Net weight 1,5 kg")?.text, "1500")
        XCTAssertEqual(LabelTextParser.package(in: "Net contents: 1 L")?.unit, .millilitre)
        XCTAssertEqual(LabelTextParser.package(in: "Net contents: 1 L")?.text, "1000")
    }
}

final class TextRecognitionTests: XCTestCase {
    /// Renders a clean label and reads it back through Vision, then through the parser.
    func testRecognisesRenderedLabelOnDevice() async throws {
        let text = "NUTRITION per 100 g\nEnergy 450 kcal\nProtein 10 g\nSugars 24 g\nINGREDIENTS: Oats, sugar, almonds."
        let size = CGSize(width: 1000, height: 700)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(in: CGRect(x: 50, y: 50, width: 900, height: 600), withAttributes: [
                .font: UIFont.systemFont(ofSize: 48),
                .foregroundColor: UIColor.black,
            ])
        }

        let recognised = try await TextRecognizer.recognize(image)
        let draft = LabelTextParser.parse(recognised)

        XCTAssertEqual(draft.basis, .per100g, recognised)
        XCTAssertEqual(draft[.energy].text, "450", recognised)
        XCTAssertEqual(draft[.protein].text, "10", recognised)
        XCTAssertEqual(draft[.totalSugars].text, "24", recognised)
        XCTAssertTrue(draft.ingredientsText.lowercased().contains("almonds"), recognised)
    }
}
