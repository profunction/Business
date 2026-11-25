-- =============================================================================
-- 种子数据（本机开发和测试用；正式上线时只保留「设定」部分，示范数据不要导入）
--   1. 设定：新山地区和送货区、餐饮打包耗材行业和分类、标准商品、月费 RM50
--   2. 示范数据：4 家示范批发商和商品、2 家示范店、1 张已送达的旧订单
--
-- 本机测试登录（supabase/config.toml 里的测试号码，验证码都是 123456）：
--   60120000001  示范店「阿明茶餐室」（试用中，看得到全部价钱）
--   60120000002  示范批发商 A 的老板
--   60120000003  登录一次后执行：update public.profiles set role = 'admin' where phone = '60120000003';
--   60120000004  示范店「Kedai Runcit Siti」（试用已用完，免费只开放 A；C 的价钱是模糊的）
--
-- 注意：送货区的邮区只是示例，正式上线前要核对。
-- 佣金比例 2%、创始会员 1% 也只是先填的数字，可以在 industries 表里改。
-- =============================================================================

-- ---------- 1. 设定 ----------

insert into public.regions (code, name) values
  ('JHB', '{"zh": "新山", "en": "Johor Bahru", "ms": "Johor Bahru"}');

insert into public.delivery_zones (region_id, code, name, postcodes, sort_order)
select r.id, v.code, v.name::jsonb, v.postcodes::text[], v.sort_order
from public.regions r
cross join (values
  ('jb_city',         '{"zh": "新山市区", "en": "JB City Centre", "ms": "Pusat Bandar JB"}',                      '{80000,80100,80150,80200,80250,80300}', 10),
  ('tebrau',          '{"zh": "地不佬 / 柔佛再也 / 奥斯汀", "en": "Tebrau / Johor Jaya / Mount Austin", "ms": "Tebrau / Johor Jaya / Mount Austin"}', '{81100}', 20),
  ('skudai',          '{"zh": "士古来", "en": "Skudai", "ms": "Skudai"}',                                        '{81300,81310}', 30),
  ('bukit_indah',     '{"zh": "武吉英达 / 淡杯", "en": "Bukit Indah / Tampoi", "ms": "Bukit Indah / Tampoi"}',      '{81200}', 40),
  ('permas_masai',    '{"zh": "百万镇 / 马西", "en": "Permas Jaya / Masai", "ms": "Permas Jaya / Masai"}',          '{81750}', 50),
  ('pasir_gudang',    '{"zh": "巴西古当", "en": "Pasir Gudang", "ms": "Pasir Gudang"}',                          '{81700}', 60),
  ('kulai',           '{"zh": "古来", "en": "Kulai", "ms": "Kulai"}',                                            '{81000}', 70),
  ('iskandar_puteri', '{"zh": "依斯干达公主城", "en": "Iskandar Puteri", "ms": "Iskandar Puteri"}',              '{79100,79200,79250}', 80)
) as v(code, name, postcodes, sort_order)
where r.code = 'JHB';

insert into public.industries (code, name, default_commission_rate, founding_commission_rate) values
  ('food_packaging',
   '{"zh": "餐饮打包耗材", "en": "Food Packaging & Disposables", "ms": "Pembungkusan Makanan & Pakai Buang"}',
   0.0200, 0.0100);

insert into public.categories (industry_id, code, name, sort_order)
select i.id, v.code, v.name::jsonb, v.sort_order
from public.industries i
cross join (values
  ('cups',            '{"zh": "杯子", "en": "Cups", "ms": "Cawan"}', 10),
  ('lids',            '{"zh": "杯盖", "en": "Lids", "ms": "Penutup"}', 20),
  ('food_containers', '{"zh": "饭盒 / 餐盒", "en": "Food Containers", "ms": "Bekas Makanan"}', 30),
  ('bowls',           '{"zh": "碗", "en": "Bowls", "ms": "Mangkuk"}', 40),
  ('plastic_bags',    '{"zh": "塑料袋", "en": "Plastic Bags", "ms": "Beg Plastik"}', 50),
  ('straws',          '{"zh": "吸管", "en": "Straws", "ms": "Straw"}', 60),
  ('cutlery',         '{"zh": "汤匙 / 叉子", "en": "Cutlery", "ms": "Sudu & Garpu"}', 70),
  ('sauce_cups',      '{"zh": "酱料杯", "en": "Sauce Cups", "ms": "Bekas Sos"}', 80),
  ('tissue',          '{"zh": "纸巾", "en": "Tissue & Napkins", "ms": "Tisu"}', 90)
) as v(code, name, sort_order)
where i.code = 'food_packaging';

insert into public.catalog_items (code, category_id, name, spec, base_unit, sort_order)
select v.code, c.id, v.name::jsonb, v.spec::jsonb, 'pcs', v.sort_order
from (values
  ('cup_pp_16oz_95',    'cups',            '{"zh": "16oz PP 透明杯（95mm 口径）", "en": "16oz PP Clear Cup (95mm)", "ms": "Cawan PP Jernih 16oz (95mm)"}', '{"capacity_oz": 16, "material": "PP", "diameter_mm": 95}', 10),
  ('cup_pp_22oz_95',    'cups',            '{"zh": "22oz PP 透明杯（95mm 口径）", "en": "22oz PP Clear Cup (95mm)", "ms": "Cawan PP Jernih 22oz (95mm)"}', '{"capacity_oz": 22, "material": "PP", "diameter_mm": 95}', 20),
  ('lid_flat_95',       'lids',            '{"zh": "95mm 平盖", "en": "95mm Flat Lid", "ms": "Penutup Rata 95mm"}', '{"diameter_mm": 95, "shape": "flat"}', 10),
  ('lid_dome_95',       'lids',            '{"zh": "95mm 拱形盖", "en": "95mm Dome Lid", "ms": "Penutup Kubah 95mm"}', '{"diameter_mm": 95, "shape": "dome"}', 20),
  ('container_rect_650','food_containers', '{"zh": "650ml 长方形饭盒（带盖）", "en": "650ml Rectangle Container with Lid", "ms": "Bekas Segi Empat 650ml dengan Penutup"}', '{"capacity_ml": 650, "material": "PP"}', 10),
  ('bowl_kraft_1000',   'bowls',           '{"zh": "1000ml 牛皮纸碗", "en": "1000ml Kraft Paper Bowl", "ms": "Mangkuk Kertas Kraf 1000ml"}', '{"capacity_ml": 1000, "material": "kraft"}', 10),
  ('bag_tshirt_medium', 'plastic_bags',    '{"zh": "背心塑料袋（中）", "en": "T-shirt Plastic Bag (Medium)", "ms": "Beg Plastik Singlet (Sederhana)"}', '{"size": "medium"}', 10),
  ('straw_6mm_black',   'straws',          '{"zh": "6mm 黑色吸管（独立包装）", "en": "6mm Black Straw (Wrapped)", "ms": "Straw Hitam 6mm (Berbalut)"}', '{"diameter_mm": 6, "wrapped": true}', 10),
  ('straw_12mm_bubble', 'straws',          '{"zh": "12mm 珍珠奶茶吸管", "en": "12mm Bubble Tea Straw", "ms": "Straw Bubble Tea 12mm"}', '{"diameter_mm": 12}', 20),
  ('spoon_plastic_white','cutlery',        '{"zh": "塑料汤匙（白色）", "en": "Plastic Spoon (White)", "ms": "Sudu Plastik (Putih)"}', '{"color": "white"}', 10),
  ('sauce_cup_1oz',     'sauce_cups',      '{"zh": "1oz 酱料杯（带盖）", "en": "1oz Sauce Cup with Lid", "ms": "Bekas Sos 1oz dengan Penutup"}', '{"capacity_oz": 1}', 10),
  ('napkin_1ply',       'tissue',          '{"zh": "餐巾纸（单层）", "en": "Napkin (1-ply)", "ms": "Tisu Napkin (1 lapis)"}', '{"ply": 1}', 10)
) as v(code, category_code, name, spec, sort_order)
join public.categories c on c.code = v.category_code;

-- 月费 RM50（创始价）
insert into public.pricing_plans (plan_code, amount_sen, is_founding, effective_from)
values ('buyer_monthly', 5000, true, '2026-01-01 00:00:00+08');

-- ---------- 2. 示范数据 ----------

-- 示范批发商（固定 id，方便 App 开发时引用）
insert into public.wholesalers (id, name, industry_id, region_id, description, address, contact_name, phone, whatsapp_phone,
                                locale, status, is_founding, order_cutoff_time, payment_terms, approved_at)
select v.id::uuid, v.name, i.id, r.id, v.description, v.address, v.contact_name, v.phone, v.phone,
       v.locale::public.app_locale, v.status::public.wholesaler_status, v.is_founding, v.cutoff::time,
       v.payment_terms::text[], case when v.status = 'active' then now() end
from public.industries i
cross join public.regions r
cross join (values
  ('00000000-0000-4000-a000-00000000000a', '示范批发 A：新山包装行', '杯子、盖子、饭盒齐全，市区当天截单 5 点', 'Jalan Demo 1, Johor Bahru', '陈老板', '60120000002', 'zh', 'active', true, '17:00', '{cod,transfer}'),
  ('00000000-0000-4000-a000-00000000000b', 'Demo Wholesaler B: Tebrau Packaging', 'Small packs available, delivery Mon-Sat', 'Jalan Demo 2, Tebrau', 'Mr Lim', '60129990002', 'en', 'active', true, '16:00', '{cod,transfer,credit}'),
  ('00000000-0000-4000-a000-00000000000c', 'Demo Pemborong C: Skudai Plastik', 'Harga borong, hantar dalam 2 hari', 'Jalan Demo 3, Skudai', 'Encik Ahmad', '60129990003', 'ms', 'active', false, null, '{cod}'),
  ('00000000-0000-4000-a000-00000000000d', '示范批发 D：待审核', '刚注册，等客服审核', 'Jalan Demo 4, Kulai', '黄小姐', '60129990004', 'zh', 'pending', false, null, '{cod}')
) as v(id, name, description, address, contact_name, phone, locale, status, is_founding, cutoff, payment_terms)
where i.code = 'food_packaging' and r.code = 'JHB';

-- 送货区和运费
insert into public.wholesaler_delivery_zones (wholesaler_id, zone_id, shipping_fee_sen, free_shipping_min_sen, min_order_sen, lead_time_days, delivery_weekdays)
select v.wholesaler_id::uuid, z.id, v.fee, v.free_min, v.min_order, v.lead_days, v.weekdays::smallint[]
from (values
  ('00000000-0000-4000-a000-00000000000a', 'jb_city',      800,  15000, 5000, 0, '{1,2,3,4,5,6}'),
  ('00000000-0000-4000-a000-00000000000a', 'tebrau',       800,  15000, 5000, 1, '{1,2,3,4,5,6}'),
  ('00000000-0000-4000-a000-00000000000a', 'skudai',       1200, 20000, 5000, 1, '{1,3,5}'),
  ('00000000-0000-4000-a000-00000000000a', 'bukit_indah',  1200, 20000, 5000, 1, '{1,3,5}'),
  ('00000000-0000-4000-a000-00000000000b', 'tebrau',       1000, 20000, 8000, 1, '{1,2,3,4,5,6}'),
  ('00000000-0000-4000-a000-00000000000b', 'jb_city',      1000, 20000, 8000, 1, '{1,2,3,4,5,6}'),
  ('00000000-0000-4000-a000-00000000000b', 'permas_masai', 1000, 20000, 8000, 1, '{1,2,3,4,5,6}'),
  ('00000000-0000-4000-a000-00000000000b', 'pasir_gudang', 1500, 25000, 8000, 2, '{2,4,6}'),
  ('00000000-0000-4000-a000-00000000000c', 'skudai',       500,  null,  3000, 2, '{1,2,3,4,5}'),
  ('00000000-0000-4000-a000-00000000000c', 'kulai',        500,  null,  3000, 2, '{1,2,3,4,5}'),
  ('00000000-0000-4000-a000-00000000000c', 'iskandar_puteri', 800, null, 3000, 2, '{1,2,3,4,5}'),
  ('00000000-0000-4000-a000-00000000000c', 'bukit_indah',  500,  null,  3000, 2, '{1,2,3,4,5}'),
  ('00000000-0000-4000-a000-00000000000c', 'tebrau',       800,  null,  3000, 2, '{1,2,3,4,5}'),
  ('00000000-0000-4000-a000-00000000000d', 'kulai',        500,  null,  null, 1, '{1,2,3,4,5,6}')
) as v(wholesaler_id, zone_code, fee, free_min, min_order, lead_days, weekdays)
join public.delivery_zones z on z.code = v.zone_code;

-- 商品：同一样东西不同包装、不同价钱，用来测试「每个多少钱」的比价
insert into public.products (wholesaler_id, catalog_item_id, category_id, name, unit, pack_qty, price_sen, min_order_qty, stock_status, status)
select v.wholesaler_id::uuid, ci.id, ci.category_id, v.name, v.unit::public.sell_unit, v.pack_qty, v.price_sen, v.moq,
       v.stock::public.stock_status, 'active'
from (values
  -- A：整箱卖
  ('00000000-0000-4000-a000-00000000000a', 'cup_pp_16oz_95',     '16安士 PP杯 95口径',        'carton', 1000, 8500,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000a', 'cup_pp_22oz_95',     '22安士 PP杯 95口径',        'carton', 1000, 9800,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000a', 'lid_flat_95',        '95 平盖',                  'carton', 1000, 4500,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000a', 'container_rect_650', '650ml 长方饭盒连盖',        'carton', 300,  7800,  1, 'low_stock'),
  ('00000000-0000-4000-a000-00000000000a', 'straw_6mm_black',    '黑色吸管 6mm 独立包',       'pack',   250,  950,   2, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000a', 'spoon_plastic_white','白色塑料汤匙',              'pack',   100,  420,   5, 'in_stock'),
  -- B：有小包装
  ('00000000-0000-4000-a000-00000000000b', 'cup_pp_16oz_95',     '16oz PP Cup 95mm (50pcs)',   'pack',   50,   480,   5, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'cup_pp_16oz_95',     '16oz PP Cup 95mm (1000pcs)', 'carton', 1000, 8800,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'lid_flat_95',        'Flat Lid 95mm (50pcs)',      'pack',   50,   260,   5, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'lid_dome_95',        'Dome Lid 95mm (1000pcs)',    'carton', 1000, 5500,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'straw_12mm_bubble',  'Bubble Straw 12mm (100pcs)', 'pack',   100,  650,   3, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'sauce_cup_1oz',      'Sauce Cup 1oz + Lid',        'carton', 2500, 9500,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000b', 'bowl_kraft_1000',    'Kraft Bowl 1000ml',          'carton', 300,  13500, 1, 'in_stock'),
  -- C：最便宜但要 2 天、没有免运费
  ('00000000-0000-4000-a000-00000000000c', 'cup_pp_16oz_95',     'Cawan PP 16oz 95mm',         'carton', 1000, 8200,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000c', 'cup_pp_22oz_95',     'Cawan PP 22oz 95mm',         'carton', 1000, 9500,  1, 'out_of_stock'),
  ('00000000-0000-4000-a000-00000000000c', 'container_rect_650', 'Bekas 650ml + Penutup',      'carton', 300,  7200,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000c', 'bag_tshirt_medium',  'Beg Singlet Sederhana',      'pack',   200,  750,   5, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000c', 'spoon_plastic_white','Sudu Plastik Putih',         'carton', 2000, 7000,  1, 'in_stock'),
  ('00000000-0000-4000-a000-00000000000c', 'napkin_1ply',        'Tisu Napkin 1 lapis',        'pack',   100,  220,   10, 'in_stock'),
  -- D：还在审核，买家看不到
  ('00000000-0000-4000-a000-00000000000d', 'cup_pp_16oz_95',     '16安士杯',                  'carton', 1000, 7900,  1, 'in_stock')
) as v(wholesaler_id, catalog_code, name, unit, pack_qty, price_sen, moq, stock)
join public.catalog_items ci on ci.code = v.catalog_code;

-- 示范店：用测试号码登录时会自动接上
insert into public.shops (id, name, shop_type, zone_id, address, contact_name, phone, whatsapp_phone, locale)
select v.id::uuid, v.name, v.shop_type::public.shop_type, z.id, v.address, v.contact_name, v.phone, v.phone, v.locale::public.app_locale
from (values
  ('00000000-0000-4000-b000-000000000001', '阿明茶餐室', 'restaurant', 'tebrau', 'Jalan Demo 10, Taman Molek', '阿明', '60120000001', 'zh'),
  ('00000000-0000-4000-b000-000000000002', 'Kedai Runcit Siti', 'grocery', 'skudai', 'Jalan Demo 20, Skudai', 'Siti', '60120000004', 'ms')
) as v(id, name, shop_type, zone_code, address, contact_name, phone, locale)
join public.delivery_zones z on z.code = v.zone_code;

-- 阿明茶餐室：试用中
select public.start_trial('00000000-0000-4000-b000-000000000001');

-- Kedai Runcit Siti：试用已经用完，免费只选了 A（送到士古来的还有 C，价钱会是模糊的）
insert into public.trial_claims (phone, shop_id, claimed_at)
values ('60120000004', '00000000-0000-4000-b000-000000000002', now() - interval '30 days');
insert into public.subscriptions (shop_id, status, started_at, trial_ends_at, locked_price_sen, is_founding_price, lapsed_at)
values ('00000000-0000-4000-b000-000000000002', 'lapsed', now() - interval '30 days', now() - interval '16 days', 5000, true, now() - interval '16 days');
insert into public.unlocked_wholesalers (shop_id, wholesaler_id) values
  ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-a000-00000000000a');

-- 阿明茶餐室的一张旧订单（已送达），这样「跟上次一样」有东西可以重复
insert into public.cart_items (shop_id, product_id, qty)
select '00000000-0000-4000-b000-000000000001', p.id, v.qty
from (values ('16安士 PP杯 95口径', 2), ('95 平盖', 2), ('白色塑料汤匙', 5)) as v(name, qty)
join public.products p on p.name = v.name and p.wholesaler_id = '00000000-0000-4000-a000-00000000000a';

select public.place_order('00000000-0000-4000-b000-000000000001', p_note => '示范订单', p_source => 'admin');

select public.confirm_order(o.id)
from public.orders o where o.shop_id = '00000000-0000-4000-b000-000000000001';
select public.set_order_status(o.id, 'delivered')
from public.orders o where o.shop_id = '00000000-0000-4000-b000-000000000001';
