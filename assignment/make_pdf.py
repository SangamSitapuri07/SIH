#!/usr/bin/env python3
"""Slave Dynasty (Mamluk) assignment — exact replica of the reference HISTORY.pdf format.

Fonts (BernardMT-Condensed, Aptos subsets) and the LPU seal were extracted from the
reference PDF itself so the look matches exactly. Body font = Times-Bold (as in ref).
Two-pass build so the Table of Content page ranges are real.
"""

from reportlab.lib.pagesizes import A4
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER
from reportlab.lib.colors import HexColor, black, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak,
    Table, TableStyle, Flowable, NextPageTemplate, KeepTogether,
)
from reportlab.lib.styles import ParagraphStyle

ASSETS = "/home/user/SIH/assignment/assets"
PAGE_W, PAGE_H = A4

pdfmetrics.registerFont(TTFont("Bernard", f"{ASSETS}/Bernard.ttf"))
pdfmetrics.registerFont(TTFont("AptosBoldNum", f"{ASSETS}/Aptos_Bold_5.ttf"))
pdfmetrics.registerFont(TTFont("AptosReg", f"{ASSETS}/Aptos_12.ttf"))
pdfmetrics.registerFont(TTFont("DejaVu", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))

BROWN = HexColor("#80340d")
BROWN2 = HexColor("#80350e")
GREEN = HexColor("#0c3512")
GRAY = HexColor("#7f7f7f")
FILL = HexColor("#f2f2f2")

# ------------------------------------------------------------------ styles
body = ParagraphStyle(
    "body", fontName="Times-Bold", fontSize=12, leading=20.8,
    alignment=TA_JUSTIFY, spaceAfter=2, spaceBefore=2,
)
bullet = ParagraphStyle(
    "bullet", parent=body, leftIndent=36, bulletIndent=18,
    bulletFontName="DejaVu", bulletFontSize=11,
)
h1 = ParagraphStyle(
    "h1", fontName="Bernard", fontSize=26, leading=30, textColor=BROWN,
    spaceAfter=8, underlineWidth=1.2, underlineOffset=-4,
)
h2 = ParagraphStyle(
    "h2", fontName="Bernard", fontSize=14, leading=18, textColor=BROWN2,
    spaceBefore=10, spaceAfter=4,
)
toc_item = ParagraphStyle("toc_item", fontName="Times-Bold", fontSize=16, leading=18)
toc_num = ParagraphStyle("toc_num", fontName="Times-Roman", fontSize=16, leading=18,
                         alignment=TA_CENTER)


def B(text):          # bullet paragraph  (➢ like the reference)
    return Paragraph(text, bullet, bulletText="\u27a2")


def P(text):
    return Paragraph(text, body)


# ------------------------------------------------------------------ cover
COVER = {
    "uni": "LOVELY PROFESSIONAL UNIVERSITY",
    "school": "SCHOOL OF LAW",
    "ca": "CA \u2013 01 HISTORY (SSC231)",
    "topic": "SLAVE DYNASTY (MAMLUK DYNASTY)",
    "by": "Submitted by :",
    "name": "Sangam Sitapuri",
    "reg": "Reg. no. \u2013 RK202406B65",
    "sec": "Course \u2013 SSC231",
    "to": "Submitted to :",
    "teacher": "Dr. Vandana Arya",
}


def draw_footer(canv, page_no):
    y = PAGE_H - 802.7          # baseline from ref
    x = 72.0
    num = str(page_no)
    canv.setFont("AptosBoldNum", 12)
    canv.setFillColor(black)
    canv.drawString(x, y, num)
    w = stringWidth(num, "AptosBoldNum", 12)
    canv.setFont("AptosReg", 12)
    canv.setFillColor(GRAY)
    canv.drawString(x + w + 2.5, y, "|")
    canv.drawString(x + w + 8.5, y, "P a g e")


def centred(canv, text, font, size, baseline_top, underline=False, color=black):
    """Draw text centred horizontally; baseline given from TOP of page (ref coords)."""
    y = PAGE_H - baseline_top
    w = stringWidth(text, font, size)
    x = (PAGE_W - w) / 2.0
    canv.setFont(font, size)
    canv.setFillColor(color)
    canv.drawString(x, y, text)
    if underline:
        canv.setStrokeColor(color)
        canv.setLineWidth(1.6)
        canv.line(x, y - 4.0, x + w, y - 4.0)


def on_cover(canv, doc):
    canv.saveState()
    centred(canv, COVER["uni"], "Bernard", 28, 99.1, underline=True)
    centred(canv, COVER["school"], "Bernard", 24, 141.9, underline=True)
    # seal logo — same rect as reference
    canv.drawImage(f"{ASSETS}/lpu_seal.jpg", 231.65, PAGE_H - 318.25,
                   width=132.0, height=133.45, mask="auto")
    centred(canv, COVER["ca"], "Bernard", 20, 408.0)
    centred(canv, COVER["topic"], "Bernard", 24, 447.4, underline=True)
    centred(canv, COVER["by"], "Bernard", 22, 527.6)
    centred(canv, COVER["name"], "Times-Bold", 18, 570.2)
    centred(canv, COVER["reg"], "Times-Bold", 18, 602.1)
    centred(canv, COVER["sec"], "Times-Bold", 18, 634.2)
    centred(canv, COVER["to"], "Bernard", 22, 702.7)
    centred(canv, COVER["teacher"], "Times-Bold", 18, 736.4, underline=True)
    draw_footer(canv, 1)
    canv.restoreState()


def on_normal(canv, doc):
    canv.saveState()
    draw_footer(canv, canv.getPageNumber())
    canv.restoreState()


class Marker(Flowable):
    """Invisible flowable that records the page it lands on."""
    def __init__(self, store, key):
        super().__init__()
        self.store, self.key = store, key
        self.width = self.height = 0

    def draw(self):
        self.store.setdefault(self.key, self.canv.getPageNumber())


class Doc(BaseDocTemplate):
    def __init__(self, path):
        super().__init__(
            path, pagesize=A4,
            leftMargin=72, rightMargin=72, topMargin=70, bottomMargin=56,
            title="Slave Dynasty (Mamluk Dynasty) - CA 01 History (SSC231)",
            author="Sangam Sitapuri",
        )
        frame = Frame(72, 56, PAGE_W - 144, PAGE_H - 126, id="main")
        self.addPageTemplates([
            PageTemplate(id="cover", frames=[frame], onPage=on_cover),
            PageTemplate(id="normal", frames=[frame], onPage=on_normal),
        ])


# ------------------------------------------------------------------ content
# Every section: (TOC label, heading text, list of elements)
# element = ("sub", text) | ("b", text) | ("p", text)

SECTIONS = [
("INTRODUCTION", "INTRODUCTION", [
("b", "The Slave Dynasty, also called the Mamluk Dynasty, ruled Delhi from 1206 to 1290 CE, and it has one of the strangest origin stories in Indian history. For almost eighty-four years, the throne of Delhi was held by men \u2014 and, for a short while, one remarkable woman \u2014 who had either been bought and sold in slave markets themselves or descended from people who had been. In most societies of that age a slave stood at the very bottom; here, slavery became a ladder to the crown."),
("b", "The word <i>mamluk</i> is Arabic and simply means 'one who is owned'. The popular textbook name 'Slave Dynasty' is catchy but slightly misleading, because no sultan actually ruled while still a slave \u2014 every one of them was legally freed, or manumitted, before he took the throne. Some historians even point out that it was not really one dynasty at all but three families in succession: those of Qutb-ud-din Aibak, Iltutmish and Balban. Still, the old name has stuck, and I will use both in this assignment."),
("b", "This period matters far beyond its length. It laid the foundation of the Delhi Sultanate, which shaped north Indian politics, administration, architecture, coinage and culture for the next three hundred years. The Qutb Minar on Delhi's skyline, the silver tanka that is an ancestor of the rupee, and the very idea of Delhi as the political heart of India all trace back to this short, violent, fascinating century."),
("b", "In the pages that follow, I have tried to tell the story of the dynasty ruler by ruler, and then to step back and look at how these former slaves governed, what they built, what daily life looked like under them, and what they finally left behind for India."),
]),

("HISTORICAL BACKGROUND AND CONTEXT", "Historical Background and Context", [
("sub", "2.1 The Turkish Invasions and the Battles of Tarain"),
("p", "The story begins outside India. Between 1175 and 1206, Shihab-ud-din Muhammad Ghori of the small Afghan principality of Ghur launched repeated campaigns into the subcontinent. His defeat at the First Battle of Tarain in 1191 at the hands of Prithviraj Chauhan was avenged the very next year at the Second Battle of Tarain (1192), which broke Rajput resistance in the north-west and opened the road to Delhi. Unlike Mahmud of Ghazni, who had come mainly to raid, Ghori came to stay: he left behind garrisons, governors and, most importantly, his trusted Turkish slave generals."),
("sub", "2.2 Who Were the Mamluks?"),
("p", "To understand how slaves became kings, one has to understand the military slave system of the medieval Islamic world. From about the ninth century, Muslim rulers had discovered that boys purchased from the Turkic steppes of Central Asia made the most reliable soldiers. A free-born noble had a clan and ambitions of his own; a slave soldier had nobody except his master. He was converted to Islam, trained rigorously in warfare, horsemanship and court manners, and promoted strictly on merit. These elite slaves, called <i>bandagan</i> in Persian sources, were nothing like plantation slaves of later centuries \u2014 they ate well, commanded armies and married into noble families. Once freed, no one in Delhi thought it shameful that a sultan had once stood in a slave market. If anything, his rise proved his worth."),
("p", "Muhammad Ghori invested heavily in such slaves. When someone pointed out that he had no son to succeed him, he is said to have replied that his thousands of Turkish slaves were his sons and would carry his name after him. Whether or not he actually spoke those words, they turned out to be prophetic."),
("sub", "2.3 The Death of Ghori and the Scramble of 1206"),
("p", "In March 1206 Ghori was assassinated at Damyak on the Indus. He left no heir \u2014 only an empire and a set of very capable, very ambitious slave officers. Three mattered most: Taj-ud-din Yildiz at Ghazni, Nasir-ud-din Qabacha at Uch and Multan, and Qutb-ud-din Aibak, commander of the Indian territories. Each began carving out his own state almost immediately. Aibak moved fastest in India: invited by the Turkish officers and citizens of Lahore, he took charge within months, and the Delhi Sultanate \u2014 an independent Indian state owing nothing to Ghazni \u2014 was born out of that decision."),
]),

("MAJOR DEVELOPMENTS AND KEY EVENTS", "Major Developments and Key Events", [
("sub", "3.1 Foundation of the Sultanate (1206\u20131210)"),
("p", "Aibak's four-year reign was short on conquest and long on consolidation, which was probably exactly what the infant state needed. He kept Yildiz out of Punjab, held the loyalty of the Turkish nobles through generosity and marriage alliances, and gave his scattered territories an administrative shape. Interestingly, he ruled from Lahore, not Delhi, because the threat from Ghazni made Punjab the sensitive frontier. He died suddenly in 1210 when his horse fell during a game of chaugan (polo). After a brief, forgettable interlude under Aram Shah, the nobles of Delhi invited Iltutmish, governor of Badaun, to the throne in 1211."),
("sub", "3.2 Consolidation under Iltutmish (1211\u20131236)"),
("p", "Iltutmish inherited a state that was really just a loose collection of military garrisons, with enemies in every direction \u2014 Yildiz claiming overlordship, Qabacha claiming Punjab, Rajput chiefs recovering their lost forts, and Bengal drifting away. He dealt with them one by one, with a patience that I find genuinely impressive. He crushed Yildiz at Tarain in 1216, broke Qabacha by 1228, recovered Ranthambore, Mandor and Gwalior, and brought Bengal back under Delhi's authority. In 1229 he received a formal letter of investiture from the Abbasid Caliph of Baghdad, which transformed the Sultanate from a soldier's improvisation into a lawful state in the eyes of the whole Islamic world."),
("sub", "3.3 The Mongol Storm of 1221"),
("p", "The most dangerous moment of the whole period came in 1221, when Chingiz Khan, pursuing the fugitive Khwarazmian prince Jalal-ud-din, appeared on the banks of the Indus. Jalal-ud-din asked Delhi for asylum. Sheltering him would have invited the most terrifying conqueror the world had ever seen straight into India; refusing him outright would have looked cowardly. Iltutmish chose survival over sentiment \u2014 with exquisite politeness he replied that Delhi's climate would not suit the prince, and quietly moved troops to make his meaning clear. The Mongols eventually withdrew. One wrong step that year and the Sultanate might have ended at thirty years old."),
("sub", "3.4 Razia and the Crisis of Succession (1236\u20131246)"),
("p", "Before his death Iltutmish did something that shocked his court: passing over his sons as incompetent, he nominated his daughter Razia as heir. The nobles ignored him and crowned Ruknuddin Firuz, whose misrule ended within seven months when the citizens of Delhi themselves helped Razia to the throne. Her energetic reign (1236\u20131240) and tragic fall are discussed in the next section. After her came a bleak decade in which the Turkish nobility, the famous 'Forty', made and unmade puppet sultans \u2014 Bahram, Masud and finally the gentle Nasiruddin Mahmud \u2014 while the Mongols sacked Lahore in 1241 and Delhi could do nothing to save it."),
("sub", "3.5 Balban's Iron Rule and the End (1266\u20131290)"),
("p", "Real power in Mahmud's reign lay with his deputy Balban, who finally took the crown himself in 1266 and ruled for twenty-one years with a policy his own chroniclers called blood and iron. He restored the terror and dignity of the crown, broke the Forty, cleared the bandit-infested roads, crushed the great Bengal revolt of Tughril, and held the Mongol frontier at the cost of his favourite son's life. But dynasties rarely survive their strongmen. Within three years of his death in 1287, his pleasure-loving grandson Kaiqubad had wrecked the administration, and in 1290 the Khalji clan seized power, killing Kaiqubad in his palace at Kilokhri. The event is remembered as the Khalji Revolution, and with it the Slave Dynasty ended."),
]),

("IMPORTANT PERSONALITIES AND THEIR CONTRIBUTIONS", "Important Personalities and Their Contributions", [
("sub", "4.1 Qutb-ud-din Aibak (r. 1206\u20131210)"),
("p", "Aibak's life reads like an adventure novel. Sold as a child at Nishapur, educated alongside the sons of the qazi who bought him, sold again, and finally purchased by Muhammad Ghori, he rose to become the real conqueror of northern India after Tarain. As ruler he was famous above all for generosity \u2014 chroniclers called him <i>Lakh Baksh</i>, the giver of lakhs. He began the Quwwat-ul-Islam mosque and the Qutb Minar at Delhi and the Adhai Din ka Jhonpra at Ajmer. His great contribution was the idea itself: that the Turkish territories in India were a separate, independent kingdom."),
("sub", "4.2 Shams-ud-din Iltutmish (r. 1211\u20131236)"),
("p", "Most historians regard Iltutmish, not Aibak, as the true founder of the Delhi Sultanate, and after studying his reign it is hard to disagree. Sold into slavery by his own jealous brothers \u2014 a story that reminds every reader of the tale of Yusuf \u2014 he rose through sheer ability. Beyond his conquests, three achievements stand out: the Caliph's investiture of 1229, which gave the Sultanate legal legitimacy; the organisation of his trusted officers into the corps of forty, the <i>Turkan-i-Chahalgani</i>; and the introduction of the silver <i>tanka</i> and copper <i>jital</i>, the standard coins of the Sultanate and, in a very real sense, ancestors of the rupee. He also made Delhi his permanent capital and turned it into a refuge for scholars fleeing the Mongol destruction of Central Asia."),
("sub", "4.3 Razia Sultan (r. 1236\u20131240)"),
("p", "Razia was the first and only woman ever to rule from the throne of Delhi. She refused to be a figurehead: she abandoned purdah, dressed in the tunic and cap of a man, led her armies in person and used the title Sultan rather than any feminine variant. The contemporary chronicler Minhaj-us-Siraj wrote that she possessed every kingly quality except her sex \u2014 a sentence that says everything about the world she was fighting. Her promotion of officers on merit, including the Abyssinian Jamal-ud-din Yaqut, enraged the Turkish nobles. In 1240 she was overthrown, and after a last bold attempt to recover Delhi with her new husband Altunia, both were killed near Kaithal. She fell, it must be said, not because she governed badly but because she governed too independently."),
("sub", "4.4 Ghiyasuddin Balban (r. 1266\u20131287)"),
("p", "Balban is the most formidable personality of the dynasty. A former slave who is said to have begun as a water-carrier, he understood the sickness of the state better than anyone: the crown had lost its awe. His cure was theatrical and ruthless at once. He declared the Sultan to be <i>Zil-e-Ilahi</i>, the Shadow of God on earth, introduced the Persian ceremonies of <i>sijda</i> (prostration) and <i>paibos</i> (kissing the royal feet), celebrated Nauroz with dazzling pomp, and famously never laughed aloud in open court. Behind the theatre stood real steel: he destroyed the power of the Forty, planted paid informers (<i>barids</i>) in every province, reorganised the army under the <i>diwan-i-arz</i>, and punished rebellion with a severity that chroniclers describe with a shudder. He conquered almost nothing new, yet without his consolidation the later expansion of the Sultanate would have been unthinkable."),
("sub", "4.5 Others Who Shaped the Age"),
("p", "Not every important figure wore a crown. Nasiruddin Mahmud (r. 1246\u20131266), pious and famously simple, kept the throne peacefully for twenty years by wisely leaving government to Balban. Minhaj-us-Siraj Juzjani wrote the <i>Tabaqat-i-Nasiri</i>, our single most important source for the whole period. At Balban's court flourished the young Amir Khusrau, later the greatest Persian poet of medieval India and a pioneer of Hindavi verse. And the Chishti sufis \u2014 Qutb-ud-din Bakhtiyar Kaki in Delhi and Baba Farid in Punjab \u2014 built bridges between communities that no sultan's decree could have built."),
]),

("POLITICAL AND ADMINISTRATIVE ASPECTS", "Political and Administrative Aspects", [
("p", "Behind the battles and palace dramas, the Mamluk sultans were quietly assembling the machinery of a state, much of it borrowed from Ghaznavid practice and some of it improvised on Indian soil. Later dynasties inherited this machinery almost intact, which is why it deserves a close look."),
("b", "<b>The Sultan.</b> At the top stood the Sultan \u2014 in theory an absolute monarch whose authority combined military power, Islamic legitimacy (hence the value of the Caliph's investiture) and, after Balban, a semi-divine aura. In practice his power depended on managing the proud Turkish nobility, as the fate of Razia and the puppet sultans shows."),
("b", "<b>The great ministries.</b> The <i>wazir</i> headed the <i>diwan-i-wizarat</i>, looking after finance and general administration. The <i>ariz-i-mamalik</i> managed recruitment, payment and inspection of the army; the <i>diwan-i-insha</i> handled royal correspondence; and the <i>sadr-us-sudur</i> and chief <i>qazi</i> looked after religious affairs, charity and justice."),
("b", "<b>The iqta system.</b> The real workhorse of the state was the <i>iqta</i>. Instead of cash salaries, officers (<i>muqtis</i>) were assigned the land revenue of a territory, from which they maintained troops, kept order and forwarded the surplus to Delhi. The iqta was not private property \u2014 strong rulers like Iltutmish and Balban transferred muqtis regularly so that none could grow local roots. As a device for ruling a huge, cash-poor, recently conquered land with a small ruling class, it was honestly quite ingenious."),
("b", "<b>Army and intelligence.</b> The army's core was heavy cavalry, supported by infantry and war elephants, which the Turks quickly learned to prize as the tanks of Indian warfare. Balban insisted on paying and mustering the central army directly, and his network of <i>barid</i> informers meant no conspiracy could hatch without Delhi hearing of it. His chain of frontier forts, garrisoned against the Mongols, gave the state a standing military spine most Indian powers of the day simply lacked."),
("b", "<b>Local society.</b> Below this Turkish superstructure, everyday India carried on. Village life, caste society and customary law continued much as before; the sultans taxed the countryside through land revenue but interfered little in its daily affairs. Justice for most people remained local; the qazi's courts served mainly the towns."),
]),

("SOCIAL AND SOCIO-ECONOMIC DIMENSIONS", "Social and Socio-Economic Dimensions", [
("p", "The economic story of the Slave Dynasty is easy to overlook but quietly impressive. The bedrock was, as always in India, agriculture, and the state's main income was land revenue drawn from the fertile plains of the doab, Punjab and the Gangetic east. What changed under the Mamluks was the framework around agriculture: sound money, safer roads and growing towns."),
("b", "<b>Currency.</b> Iltutmish's silver tanka of about 175 grains and the copper jital deserve special mention, because sound money is the least glamorous and most useful thing a medieval state could provide. A trader in Lahore and a grain dealer in Badaun could now settle accounts in the same reliable coin stamped with the Sultan's name \u2014 an advertisement of stability circulating in thousands of pockets."),
("b", "<b>Towns and trade.</b> Delhi's mints, markets and caravanserais grew together, and the city's population swelled with soldiers, artisans, refugees and the enormous service economy that a court generates. Multan, Badaun and Lakhnauti flourished as provincial capitals, linked by routes running west to Persia and east into Bengal's river network. After Balban cleared the Mewati bandits from the roads around Delhi, travellers and merchants could move safely again \u2014 something ordinary people surely valued more than court ceremony."),
("b", "<b>A layered society.</b> Urban society was a polyglot affair: Turkish nobles, Persian-speaking clerks and poets, Indian Muslim artisans, and the Hindu majority of traders, bankers and craftsmen without whom the whole system would have stopped dead, since credit and long-distance commerce remained largely in Indian merchant hands. In the countryside life changed far less; the peasant's relationship with the state was still mediated through village headmen, only now the revenue demand travelled up through a muqti to Delhi."),
("b", "<b>The other side.</b> It was not an egalitarian world by any stretch, and the punitive campaigns of the period fell brutally on ordinary people in their path. But the broad picture of the later thirteenth century, particularly under Balban's peace, is one of recovering trade, expanding towns and a countryside slowly adjusting to a new, more centralised state."),
]),

("CULTURAL ASPECTS", "Cultural Aspects", [
("p", "Culture under the Slave Dynasty was shaped by a terrible irony: the Mongol devastation of Central Asia and Persia, horrific as it was, produced an unexpected windfall for Delhi. Scholars, poets, sufis, artisans and administrators fleeing the destruction poured into the one great Muslim capital still standing safely, and the sultans \u2014 especially Iltutmish and Balban \u2014 welcomed them. Contemporaries began comparing Delhi to Baghdad and Cairo."),
("b", "<b>Literature and learning.</b> Persian became the language of administration and high culture. Minhaj-us-Siraj wrote his great history, the <i>Tabaqat-i-Nasiri</i>, at the court of Nasiruddin Mahmud; practically everything we know about the period rests on his pages, read critically. In the circle of Balban's son Prince Muhammad at Multan flourished the young Amir Khusrau, whose experiments with Hindavi verse make him a distant ancestor of Hindi-Urdu literature."),
("b", "<b>The sufi saints.</b> The Chishti hospices of Qutb-ud-din Bakhtiyar Kaki in Delhi and Baba Farid in Punjab welcomed everyone, Hindu and Muslim alike, and their tradition of devotional music and inclusive piety became a permanent feature of Indian religious life. Many believe the Qutb Minar is at least partly named after Kaki rather than Aibak \u2014 a nice reminder that saints could outshine sultans in popular memory."),
("b", "<b>Court culture.</b> Balban's Persianised court \u2014 Nauroz celebrations, strict etiquette, tall guards with drawn swords \u2014 set the ceremonial template that every later Delhi dynasty, down to the Mughals, would elaborate. We might find his obsession with appearances theatrical, but it worked: the awe of the crown, which had evaporated after Iltutmish, returned."),
]),

("ART AND ARCHITECTURE", "Art and Architecture", [
("p", "For me, the most tangible way to connect with the Slave Dynasty is to stand in the Qutb complex at Mehrauli in Delhi, because there the dynasty is still physically present."),
("b", "<b>Quwwat-ul-Islam mosque.</b> Begun by Aibak in the 1190s, this was the first great mosque of Delhi, famously raised on carved pillars taken from earlier temples, so that lotuses, bells and chains peep out from the arcades of a mosque. Whatever one feels about the politics of that reuse, the visual result is a startling record of two artistic worlds colliding and, eventually, merging. Aibak's Adhai Din ka Jhonpra at Ajmer shows the same hybrid energy."),
("b", "<b>The Qutb Minar.</b> Begun by Aibak as a tower of victory and completed by Iltutmish, who added three storeys, it stands about 72.5 metres tall \u2014 still the tallest brick minaret in the world \u2014 ribbed and fluted in red sandstone and wrapped in bands of Quranic calligraphy."),
("b", "<b>Tombs.</b> Iltutmish built a magnificently carved tomb for himself behind the mosque, and the Sultan Ghari tomb for his eldest son \u2014 the earliest surviving Islamic tomb in India. Balban's ruined tomb at Mehrauli, plain today, is historically important because it contains one of the first true arches built in India, a small technical detail that announced a whole new architectural future leading eventually to the domes of the Mughals."),
]),

("IMPACT AND HISTORICAL SIGNIFICANCE", "Impact and Historical Significance", [
("p", "Measured in territory, the Slave Dynasty's achievement was modest; the map of 1290 was not dramatically larger than the map of 1210. Measured in foundations, it was enormous."),
("b", "<b>Political.</b> The dynasty established Delhi as the imperial centre of India \u2014 a status the city has never really lost \u2014 and created the model of the Sultan as an absolute, semi-sacred ruler, which Balban perfected and every later dynasty inherited."),
("b", "<b>Administrative.</b> It gave India the iqta system, the great ministries, the barid intelligence network and the idea of a centrally paid, centrally mustered army. The tanka-jital currency anchored north Indian commerce for generations."),
("b", "<b>Strategic.</b> Its stubborn defence of the north-west \u2014 from Iltutmish's cold refusal of Jalal-ud-din in 1221 to Balban's frontier forts \u2014 kept the Mongol catastrophe, which annihilated Baghdad in 1258, from engulfing India. That may well be its greatest single service, and one we rarely stop to appreciate: India's cities were never burned the way Merv, Nishapur or Baghdad were."),
("b", "<b>Cultural.</b> The fusion that began under the Mamluks \u2014 in the arcades of the Quwwat-ul-Islam mosque, the verses of Amir Khusrau, the hospices of the Chishti saints \u2014 set Indian civilisation on the path toward the Indo-Islamic synthesis: new styles of building, new genres of music and poetry, new words and eventually new languages."),
("b", "<b>A meritocratic idea.</b> There is a subtler legacy too. A polity in which a slave could become sultan, and a woman could \u2014 however briefly \u2014 rule an empire, carried within it a startlingly modern idea for the thirteenth century: that the throne could be earned. The Turkish nobles strangled that idea in Razia's case, but the precedent had been set."),
]),

("CONTRIBUTION TO THE WIDER UNDERSTANDING OF INDIAN HISTORY", "Contribution to the Wider Understanding of Indian History", [
("b", "Studying the Slave Dynasty changes how we read the centuries that follow. The Khalji and Tughlaq empires, and in many ways even the Mughal state, were built on scaffolding erected between 1206 and 1290 \u2014 the capital at Delhi, the revenue machinery, the standing army, the court ceremonial. When later rulers expanded south, they were expanding a state that the Mamluks had first made stable enough to expand."),
("b", "The period also complicates lazy stereotypes. It shows a 'Muslim' ruling class that was itself deeply divided \u2014 Turk against Tajik, noble against crown \u2014 and an Indian society that engaged with the newcomers in every register, from resistance to partnership. The commercial classes who financed the Sultanate's trade were largely Hindu; the saints most loved by ordinary Muslims preached in local dialects and welcomed non-Muslims into their hospices."),
("b", "Finally, the dynasty is a lesson in how historians work. Almost everything we know comes from a handful of Persian chronicles written by men close to power, above all Minhaj-us-Siraj, who dedicated his book to a reigning sultan. Reading such sources critically \u2014 asking who is speaking, for whom and why \u2014 is exactly the skill this period forces a student of history to learn."),
]),

("CONCLUSION", "Conclusion", [
("b", "Working through this topic, what stayed with me is not any single battle or building but the strange arc of the whole story: an empire founded by men who had once been merchandise. Aibak turned a dead conqueror's garrisons into a kingdom and gave it its first monuments. Iltutmish, sold into slavery by his own brothers, gave that kingdom law, money, institutions and international recognition \u2014 and saved it from Chingiz Khan with a single, brilliantly evasive letter. Razia showed how far ability could carry a person in that world, and her fate showed exactly where the limits lay. Balban, the water-carrier who became the Shadow of God, rebuilt the majesty of the crown with equal parts ceremony and cruelty, and held the Mongol frontier at the cost of his beloved son."),
("b", "Eighty-four years is not long \u2014 less than a single modern lifetime \u2014 yet within it the Delhi Sultanate went from an improvised military occupation to a settled state with a capital, a currency, an administration and a culture of its own. The dynasties that followed built higher, but they built on this foundation. That, in the end, is the claim of the Slave Dynasty on our memory: not that its sultans were saints \u2014 they emphatically were not \u2014 but that they were builders in the deepest sense, and that they proved, in an age obsessed with bloodlines, that the throne of Delhi could be earned."),
]),

("BIBILIOGRAPHY", "Bibliography", [
("p", "1. Satish Chandra, <i>History of Medieval India (800\u20131700)</i>, Orient BlackSwan, New Delhi."),
("p", "2. A. B. M. Habibullah, <i>The Foundation of Muslim Rule in India</i>, Central Book Depot, Allahabad."),
("p", "3. Peter Jackson, <i>The Delhi Sultanate: A Political and Military History</i>, Cambridge University Press."),
("p", "4. Minhaj-us-Siraj Juzjani, <i>Tabaqat-i-Nasiri</i>, translated by H. G. Raverty."),
("p", "5. J. L. Mehta, <i>Advanced Study in the History of Medieval India</i>, Vol. I, Sterling Publishers, New Delhi."),
("p", "6. NCERT, <i>Themes in Indian History</i>, Part II, New Delhi."),
("p", "7. A. L. Srivastava, <i>The Sultanate of Delhi</i>, Shiva Lal Agarwala and Co., Agra."),
]),
]


def heading_par(text):
    return Paragraph(f"<u>{text}</u>", h1)


def build_story(page_map=None):
    """page_map: dict key->page collected in pass 1 (None on first pass)."""
    marks = {}
    story = [NextPageTemplate("normal"), PageBreak()]

    # ---------------- TOC page (page 2)
    story.append(Paragraph(f'<font color="#0c3512"><u>TABLE OF CONTENT</u></font>',
                           ParagraphStyle("toct", fontName="Bernard", fontSize=36,
                                          leading=40, textColor=GREEN, spaceAfter=14)))
    rows, styles_cmds = [], []
    r = 0
    for i, (label, _, _) in enumerate(SECTIONS, start=1):
        if page_map:
            s = page_map.get(f"s{i}", 0)
            e = page_map.get(f"e{i}", s)
            pg = f"{s:02d}" if e <= s else f"{s:02d} - {e:02d}"
        else:
            pg = "00"
        rows.append([Paragraph(f"<b>{i}.  {label}</b>", toc_item),
                     Paragraph(pg, toc_num)])
        styles_cmds += [
            ("BACKGROUND", (0, r), (-1, r), FILL),
            ("VALIGN", (0, r), (-1, r), "MIDDLE"),
            ("TOPPADDING", (0, r), (-1, r), 6),
            ("BOTTOMPADDING", (0, r), (-1, r), 6),
            ("LEFTPADDING", (0, r), (0, r), 8),
        ]
        rows.append(["", ""])  # white gap row
        styles_cmds.append(("TOPPADDING", (0, r + 1), (-1, r + 1), 0))
        styles_cmds.append(("BOTTOMPADDING", (0, r + 1), (-1, r + 1), 0))
        r += 2
    gap_h = 7
    heights = []
    for j in range(len(rows)):
        heights.append(None if j % 2 == 0 else gap_h)
    toc = Table(rows, colWidths=[365, 86], rowHeights=heights)
    toc.setStyle(TableStyle(styles_cmds))
    story.append(toc)
    story.append(PageBreak())

    # ---------------- content sections
    for i, (label, heading, elements) in enumerate(SECTIONS, start=1):
        story.append(Marker(marks, f"s{i}"))
        story.append(heading_par(heading))
        for kind, text in elements:
            if kind == "sub":
                story.append(Paragraph(text, h2))
            elif kind == "b":
                story.append(B(text))
                story.append(Spacer(1, 6))
            else:
                story.append(P(text))
                story.append(Spacer(1, 8))
        story.append(Marker(marks, f"e{i}"))
        if i < len(SECTIONS):
            story.append(PageBreak())

    return story, marks


OUT = "/home/user/SIH/assignment/Slave_Dynasty_Mamluk_Assignment.pdf"

# pass 1 — collect real page numbers
doc = Doc("/tmp/_pass1.pdf")
story, marks = build_story(None)
doc.build(story)
page_map = dict(marks)

# pass 2 — final with real TOC numbers
doc = Doc(OUT)
story, _ = build_story(page_map)
doc.build(story)
print("built", OUT)
print("sections at:", {k: v for k, v in sorted(page_map.items())})
